//============================================================================
// multicore_noc_top.sv — 4-Core RV32I SoC with AXI-Lite NoC
//
// Architecture:
//   - 4 × RV32I 5-stage pipelined cores (HART_ID 0–3)
//   - Each core has a private instruction read path (ROM + RAM)
//   - All data accesses go through AXI-Lite master bridges
//   - 4×5 AXI-Lite crossbar interconnect
//   - 5 shared slaves: Boot ROM, Main RAM, UART, Timer, SYSCTRL
//   - Slave bridges convert AXI back to simple peripheral bus
//
// Memory Map (from soc_pkg):
//   0x0000_0000 : Boot ROM   (16 KB, read-only)
//   0x8000_0000 : Main RAM   (64 KB, shared R/W)
//   0xF000_0000 : UART
//   0xF001_0000 : Timer
//   0xF002_0000 : System Control
//============================================================================

module multicore_noc_top
    import soc_pkg::*;
    import axi_pkg::*;
#(
    parameter int NUM_CORES     = 4,
    parameter     ROM_INIT_FILE = "",
    parameter     RAM_INIT_FILE = ""
)(
    input  logic        clk,
    input  logic        rst_n,

    // External UART
    output logic        uart_tx,
    input  logic        uart_rx,

    // Interrupts
    output logic        irq_timer,
    output logic        irq_uart_tx
);

    // =======================================================================
    //  Core instances + instruction memory paths
    // =======================================================================

    // Core memory interface wires
    logic [31:0] core_imem_addr  [0:NUM_CORES-1];
    logic [31:0] core_imem_rdata [0:NUM_CORES-1];
    logic        core_imem_req   [0:NUM_CORES-1];
    logic        core_imem_valid [0:NUM_CORES-1];

    logic [31:0] core_dmem_addr  [0:NUM_CORES-1];
    logic [31:0] core_dmem_wdata [0:NUM_CORES-1];
    logic [31:0] core_dmem_rdata [0:NUM_CORES-1];
    logic        core_dmem_rd    [0:NUM_CORES-1];
    logic        core_dmem_wr    [0:NUM_CORES-1];
    logic [3:0]  core_dmem_be    [0:NUM_CORES-1];
    logic        core_dmem_valid [0:NUM_CORES-1];

    // Per-core instruction ROM and RAM read ports
    logic [31:0] iro_rdata [0:NUM_CORES-1];
    logic        iro_valid [0:NUM_CORES-1];
    logic [31:0] ira_rdata [0:NUM_CORES-1];
    logic        ira_valid [0:NUM_CORES-1];

    generate
        for (genvar ci = 0; ci < NUM_CORES; ci++) begin : gen_cores

            // ---- Core ----
            rv32i_core #(
                .HART_ID   (ci),
                .RESET_PC  (ROM_BASE)
            ) u_core (
                .clk        (clk),
                .rst_n      (rst_n),
                .imem_addr  (core_imem_addr[ci]),
                .imem_rdata (core_imem_rdata[ci]),
                .imem_req   (core_imem_req[ci]),
                .imem_valid (core_imem_valid[ci]),
                .dmem_addr  (core_dmem_addr[ci]),
                .dmem_wdata (core_dmem_wdata[ci]),
                .dmem_rdata (core_dmem_rdata[ci]),
                .dmem_rd    (core_dmem_rd[ci]),
                .dmem_wr    (core_dmem_wr[ci]),
                .dmem_be    (core_dmem_be[ci]),
                .dmem_valid (core_dmem_valid[ci])
            );

            // ---- Instruction ROM read port (private per core) ----
            boot_rom #(
                .DEPTH         (4096),
                .MEM_INIT_FILE (ROM_INIT_FILE)
            ) u_irom (
                .clk   (clk),
                .rst_n (rst_n),
                .addr  ({20'b0, core_imem_addr[ci][13:0]}),
                .rd_en (core_imem_req[ci] && !core_imem_addr[ci][31]),
                .rdata (iro_rdata[ci]),
                .valid (iro_valid[ci])
            );

            // ---- Instruction RAM read port (private per core) ----
            sram #(
                .DEPTH         (16384),
                .MEM_INIT_FILE (RAM_INIT_FILE)
            ) u_iram (
                .clk   (clk),
                .rst_n (rst_n),
                .addr  ({16'b0, core_imem_addr[ci][15:0]}),
                .wdata ('0),
                .rd_en (core_imem_req[ci] && core_imem_addr[ci][31]),
                .wr_en (1'b0),
                .be    (4'b0),
                .rdata (ira_rdata[ci]),
                .valid (ira_valid[ci])
            );

            // ---- Instruction mux: ROM (addr[31]=0) or RAM (addr[31]=1) ----
            wire imem_from_ram = core_imem_addr[ci][31];

            assign core_imem_rdata[ci] = imem_from_ram ? ira_rdata[ci] : iro_rdata[ci];
            assign core_imem_valid[ci] = imem_from_ram ? ira_valid[ci] : iro_valid[ci];

        end
    endgenerate

    // =======================================================================
    //  AXI Master Bridges (one per core data port)
    // =======================================================================

    // AXI signals per master
    logic [31:0] ma_awaddr [0:NUM_CORES-1];
    logic [2:0]  ma_awprot [0:NUM_CORES-1];
    logic        ma_awvalid[0:NUM_CORES-1];
    logic        ma_awready[0:NUM_CORES-1];
    logic [31:0] ma_wdata  [0:NUM_CORES-1];
    logic [3:0]  ma_wstrb  [0:NUM_CORES-1];
    logic        ma_wvalid [0:NUM_CORES-1];
    logic        ma_wready [0:NUM_CORES-1];
    logic [1:0]  ma_bresp  [0:NUM_CORES-1];
    logic        ma_bvalid [0:NUM_CORES-1];
    logic        ma_bready [0:NUM_CORES-1];
    logic [31:0] ma_araddr [0:NUM_CORES-1];
    logic [2:0]  ma_arprot [0:NUM_CORES-1];
    logic        ma_arvalid[0:NUM_CORES-1];
    logic        ma_arready[0:NUM_CORES-1];
    logic [31:0] ma_rdata  [0:NUM_CORES-1];
    logic [1:0]  ma_rresp  [0:NUM_CORES-1];
    logic        ma_rvalid [0:NUM_CORES-1];
    logic        ma_rready [0:NUM_CORES-1];

    generate
        for (genvar ci = 0; ci < NUM_CORES; ci++) begin : gen_axi_masters
            axi_lite_master u_axi_master (
                .clk        (clk),
                .rst_n      (rst_n),
                .core_addr  (core_dmem_addr[ci]),
                .core_wdata (core_dmem_wdata[ci]),
                .core_rd    (core_dmem_rd[ci]),
                .core_wr    (core_dmem_wr[ci]),
                .core_be    (core_dmem_be[ci]),
                .core_rdata (core_dmem_rdata[ci]),
                .core_valid (core_dmem_valid[ci]),
                .m_axi_awaddr  (ma_awaddr[ci]),
                .m_axi_awprot  (ma_awprot[ci]),
                .m_axi_awvalid (ma_awvalid[ci]),
                .m_axi_awready (ma_awready[ci]),
                .m_axi_wdata   (ma_wdata[ci]),
                .m_axi_wstrb   (ma_wstrb[ci]),
                .m_axi_wvalid  (ma_wvalid[ci]),
                .m_axi_wready  (ma_wready[ci]),
                .m_axi_bresp   (ma_bresp[ci]),
                .m_axi_bvalid  (ma_bvalid[ci]),
                .m_axi_bready  (ma_bready[ci]),
                .m_axi_araddr  (ma_araddr[ci]),
                .m_axi_arprot  (ma_arprot[ci]),
                .m_axi_arvalid (ma_arvalid[ci]),
                .m_axi_arready (ma_arready[ci]),
                .m_axi_rdata   (ma_rdata[ci]),
                .m_axi_rresp   (ma_rresp[ci]),
                .m_axi_rvalid  (ma_rvalid[ci]),
                .m_axi_rready  (ma_rready[ci])
            );
        end
    endgenerate

    // =======================================================================
    //  AXI-Lite Crossbar (4 masters × 5 slaves)
    // =======================================================================

    // Slave-side AXI signals
    logic [31:0] sa_awaddr [0:4]; logic [2:0] sa_awprot [0:4]; logic sa_awvalid[0:4]; logic sa_awready[0:4];
    logic [31:0] sa_wdata  [0:4]; logic [3:0] sa_wstrb  [0:4]; logic sa_wvalid [0:4]; logic sa_wready [0:4];
    logic [1:0]  sa_bresp  [0:4]; logic sa_bvalid[0:4]; logic sa_bready[0:4];
    logic [31:0] sa_araddr [0:4]; logic [2:0] sa_arprot [0:4]; logic sa_arvalid[0:4]; logic sa_arready[0:4];
    logic [31:0] sa_rdata  [0:4]; logic [1:0] sa_rresp  [0:4]; logic sa_rvalid [0:4]; logic sa_rready [0:4];

    axi_lite_xbar #(
        .NUM_MASTERS (4),
        .NUM_SLAVES  (5)
    ) u_xbar (
        .clk   (clk),
        .rst_n (rst_n),
        // Master 0
        .m0_awaddr(ma_awaddr[0]), .m0_awprot(ma_awprot[0]), .m0_awvalid(ma_awvalid[0]), .m0_awready(ma_awready[0]),
        .m0_wdata(ma_wdata[0]), .m0_wstrb(ma_wstrb[0]), .m0_wvalid(ma_wvalid[0]), .m0_wready(ma_wready[0]),
        .m0_bresp(ma_bresp[0]), .m0_bvalid(ma_bvalid[0]), .m0_bready(ma_bready[0]),
        .m0_araddr(ma_araddr[0]), .m0_arprot(ma_arprot[0]), .m0_arvalid(ma_arvalid[0]), .m0_arready(ma_arready[0]),
        .m0_rdata(ma_rdata[0]), .m0_rresp(ma_rresp[0]), .m0_rvalid(ma_rvalid[0]), .m0_rready(ma_rready[0]),
        // Master 1
        .m1_awaddr(ma_awaddr[1]), .m1_awprot(ma_awprot[1]), .m1_awvalid(ma_awvalid[1]), .m1_awready(ma_awready[1]),
        .m1_wdata(ma_wdata[1]), .m1_wstrb(ma_wstrb[1]), .m1_wvalid(ma_wvalid[1]), .m1_wready(ma_wready[1]),
        .m1_bresp(ma_bresp[1]), .m1_bvalid(ma_bvalid[1]), .m1_bready(ma_bready[1]),
        .m1_araddr(ma_araddr[1]), .m1_arprot(ma_arprot[1]), .m1_arvalid(ma_arvalid[1]), .m1_arready(ma_arready[1]),
        .m1_rdata(ma_rdata[1]), .m1_rresp(ma_rresp[1]), .m1_rvalid(ma_rvalid[1]), .m1_rready(ma_rready[1]),
        // Master 2
        .m2_awaddr(ma_awaddr[2]), .m2_awprot(ma_awprot[2]), .m2_awvalid(ma_awvalid[2]), .m2_awready(ma_awready[2]),
        .m2_wdata(ma_wdata[2]), .m2_wstrb(ma_wstrb[2]), .m2_wvalid(ma_wvalid[2]), .m2_wready(ma_wready[2]),
        .m2_bresp(ma_bresp[2]), .m2_bvalid(ma_bvalid[2]), .m2_bready(ma_bready[2]),
        .m2_araddr(ma_araddr[2]), .m2_arprot(ma_arprot[2]), .m2_arvalid(ma_arvalid[2]), .m2_arready(ma_arready[2]),
        .m2_rdata(ma_rdata[2]), .m2_rresp(ma_rresp[2]), .m2_rvalid(ma_rvalid[2]), .m2_rready(ma_rready[2]),
        // Master 3
        .m3_awaddr(ma_awaddr[3]), .m3_awprot(ma_awprot[3]), .m3_awvalid(ma_awvalid[3]), .m3_awready(ma_awready[3]),
        .m3_wdata(ma_wdata[3]), .m3_wstrb(ma_wstrb[3]), .m3_wvalid(ma_wvalid[3]), .m3_wready(ma_wready[3]),
        .m3_bresp(ma_bresp[3]), .m3_bvalid(ma_bvalid[3]), .m3_bready(ma_bready[3]),
        .m3_araddr(ma_araddr[3]), .m3_arprot(ma_arprot[3]), .m3_arvalid(ma_arvalid[3]), .m3_arready(ma_arready[3]),
        .m3_rdata(ma_rdata[3]), .m3_rresp(ma_rresp[3]), .m3_rvalid(ma_rvalid[3]), .m3_rready(ma_rready[3]),
        // Slaves
        .s0_awaddr(sa_awaddr[0]),.s0_awprot(sa_awprot[0]),.s0_awvalid(sa_awvalid[0]),.s0_awready(sa_awready[0]),
        .s0_wdata(sa_wdata[0]),.s0_wstrb(sa_wstrb[0]),.s0_wvalid(sa_wvalid[0]),.s0_wready(sa_wready[0]),
        .s0_bresp(sa_bresp[0]),.s0_bvalid(sa_bvalid[0]),.s0_bready(sa_bready[0]),
        .s0_araddr(sa_araddr[0]),.s0_arprot(sa_arprot[0]),.s0_arvalid(sa_arvalid[0]),.s0_arready(sa_arready[0]),
        .s0_rdata(sa_rdata[0]),.s0_rresp(sa_rresp[0]),.s0_rvalid(sa_rvalid[0]),.s0_rready(sa_rready[0]),

        .s1_awaddr(sa_awaddr[1]),.s1_awprot(sa_awprot[1]),.s1_awvalid(sa_awvalid[1]),.s1_awready(sa_awready[1]),
        .s1_wdata(sa_wdata[1]),.s1_wstrb(sa_wstrb[1]),.s1_wvalid(sa_wvalid[1]),.s1_wready(sa_wready[1]),
        .s1_bresp(sa_bresp[1]),.s1_bvalid(sa_bvalid[1]),.s1_bready(sa_bready[1]),
        .s1_araddr(sa_araddr[1]),.s1_arprot(sa_arprot[1]),.s1_arvalid(sa_arvalid[1]),.s1_arready(sa_arready[1]),
        .s1_rdata(sa_rdata[1]),.s1_rresp(sa_rresp[1]),.s1_rvalid(sa_rvalid[1]),.s1_rready(sa_rready[1]),

        .s2_awaddr(sa_awaddr[2]),.s2_awprot(sa_awprot[2]),.s2_awvalid(sa_awvalid[2]),.s2_awready(sa_awready[2]),
        .s2_wdata(sa_wdata[2]),.s2_wstrb(sa_wstrb[2]),.s2_wvalid(sa_wvalid[2]),.s2_wready(sa_wready[2]),
        .s2_bresp(sa_bresp[2]),.s2_bvalid(sa_bvalid[2]),.s2_bready(sa_bready[2]),
        .s2_araddr(sa_araddr[2]),.s2_arprot(sa_arprot[2]),.s2_arvalid(sa_arvalid[2]),.s2_arready(sa_arready[2]),
        .s2_rdata(sa_rdata[2]),.s2_rresp(sa_rresp[2]),.s2_rvalid(sa_rvalid[2]),.s2_rready(sa_rready[2]),

        .s3_awaddr(sa_awaddr[3]),.s3_awprot(sa_awprot[3]),.s3_awvalid(sa_awvalid[3]),.s3_awready(sa_awready[3]),
        .s3_wdata(sa_wdata[3]),.s3_wstrb(sa_wstrb[3]),.s3_wvalid(sa_wvalid[3]),.s3_wready(sa_wready[3]),
        .s3_bresp(sa_bresp[3]),.s3_bvalid(sa_bvalid[3]),.s3_bready(sa_bready[3]),
        .s3_araddr(sa_araddr[3]),.s3_arprot(sa_arprot[3]),.s3_arvalid(sa_arvalid[3]),.s3_arready(sa_arready[3]),
        .s3_rdata(sa_rdata[3]),.s3_rresp(sa_rresp[3]),.s3_rvalid(sa_rvalid[3]),.s3_rready(sa_rready[3]),

        .s4_awaddr(sa_awaddr[4]),.s4_awprot(sa_awprot[4]),.s4_awvalid(sa_awvalid[4]),.s4_awready(sa_awready[4]),
        .s4_wdata(sa_wdata[4]),.s4_wstrb(sa_wstrb[4]),.s4_wvalid(sa_wvalid[4]),.s4_wready(sa_wready[4]),
        .s4_bresp(sa_bresp[4]),.s4_bvalid(sa_bvalid[4]),.s4_bready(sa_bready[4]),
        .s4_araddr(sa_araddr[4]),.s4_arprot(sa_arprot[4]),.s4_arvalid(sa_arvalid[4]),.s4_arready(sa_arready[4]),
        .s4_rdata(sa_rdata[4]),.s4_rresp(sa_rresp[4]),.s4_rvalid(sa_rvalid[4]),.s4_rready(sa_rready[4])
    );

    // =======================================================================
    //  AXI Slave Bridges → Peripheral Bus
    // =======================================================================
    logic [31:0] p_addr  [0:4];
    logic [31:0] p_wdata [0:4];
    logic        p_rd    [0:4];
    logic        p_wr    [0:4];
    logic [3:0]  p_be    [0:4];
    logic [31:0] p_rdata [0:4];
    logic        p_valid [0:4];

    generate
        for (genvar si = 0; si < 5; si++) begin : gen_axi_slaves
            axi_lite_slave u_axi_slave (
                .clk(clk), .rst_n(rst_n),
                .s_axi_awaddr(sa_awaddr[si]), .s_axi_awprot(sa_awprot[si]),
                .s_axi_awvalid(sa_awvalid[si]), .s_axi_awready(sa_awready[si]),
                .s_axi_wdata(sa_wdata[si]), .s_axi_wstrb(sa_wstrb[si]),
                .s_axi_wvalid(sa_wvalid[si]), .s_axi_wready(sa_wready[si]),
                .s_axi_bresp(sa_bresp[si]), .s_axi_bvalid(sa_bvalid[si]),
                .s_axi_bready(sa_bready[si]),
                .s_axi_araddr(sa_araddr[si]), .s_axi_arprot(sa_arprot[si]),
                .s_axi_arvalid(sa_arvalid[si]), .s_axi_arready(sa_arready[si]),
                .s_axi_rdata(sa_rdata[si]), .s_axi_rresp(sa_rresp[si]),
                .s_axi_rvalid(sa_rvalid[si]), .s_axi_rready(sa_rready[si]),
                .periph_addr(p_addr[si]), .periph_wdata(p_wdata[si]),
                .periph_rd(p_rd[si]), .periph_wr(p_wr[si]),
                .periph_be(p_be[si]), .periph_rdata(p_rdata[si]),
                .periph_valid(p_valid[si])
            );
        end
    endgenerate

    // =======================================================================
    //  Shared Peripherals
    // =======================================================================

    // ---- Slave 0: Boot ROM (data-side read access) ----
    boot_rom #(
        .DEPTH         (4096),
        .MEM_INIT_FILE (ROM_INIT_FILE)
    ) u_data_rom (
        .clk   (clk),
        .rst_n (rst_n),
        .addr  (p_addr[0]),
        .rd_en (p_rd[0]),
        .rdata (p_rdata[0]),
        .valid (p_valid[0])
    );

    // ---- Slave 1: Main SRAM (shared read/write) ----
    sram #(
        .DEPTH         (16384),
        .MEM_INIT_FILE (RAM_INIT_FILE)
    ) u_main_ram (
        .clk   (clk),
        .rst_n (rst_n),
        .addr  (p_addr[1]),
        .wdata (p_wdata[1]),
        .rd_en (p_rd[1]),
        .wr_en (p_wr[1]),
        .be    (p_be[1]),
        .rdata (p_rdata[1]),
        .valid (p_valid[1])
    );

    // ---- Slave 2: UART ----
    uart #(
        .DEFAULT_BAUD_DIV (868)
    ) u_uart (
        .clk         (clk),
        .rst_n       (rst_n),
        .addr        (p_addr[2]),
        .wdata       (p_wdata[2]),
        .rd_en       (p_rd[2]),
        .wr_en       (p_wr[2]),
        .be          (p_be[2]),
        .rdata       (p_rdata[2]),
        .valid       (p_valid[2]),
        .uart_tx     (uart_tx),
        .uart_rx     (uart_rx),
        .irq_tx_done (irq_uart_tx)
    );

    // ---- Slave 3: Timer ----
    timer u_timer (
        .clk       (clk),
        .rst_n     (rst_n),
        .addr      (p_addr[3]),
        .wdata     (p_wdata[3]),
        .rd_en     (p_rd[3]),
        .wr_en     (p_wr[3]),
        .be        (p_be[3]),
        .rdata     (p_rdata[3]),
        .valid     (p_valid[3]),
        .irq_timer (irq_timer)
    );

    // ---- Slave 4: System Control ----
    // HART_ID here is 0 since the register returns a fixed value;
    // each core reads its own HART_ID via a per-core mechanism.
    // For multi-core, the SYSCTRL returns core 0's ID.
    // A smarter design would route HART_ID based on which master
    // is currently accessing. For now cores use software convention.
    sys_ctrl #(
        .HART_ID           (0),
        .NUM_HARTS         (NUM_CORES),
        .DEFAULT_BOOT_ADDR (ROM_BASE)
    ) u_sysctrl (
        .clk   (clk),
        .rst_n (rst_n),
        .addr  (p_addr[4]),
        .wdata (p_wdata[4]),
        .rd_en (p_rd[4]),
        .wr_en (p_wr[4]),
        .be    (p_be[4]),
        .rdata (p_rdata[4]),
        .valid (p_valid[4])
    );

endmodule