//============================================================================
// riscv_soc_top.sv — Single-Core RV32I SoC Top Level
//
// Instantiates and connects:
//   - RV32I 5-stage pipelined core
//   - Bus interconnect (address decode + mux)
//   - Boot ROM (16 KB)
//   - Main SRAM (64 KB)
//   - UART (TX with FIFO)
//   - Timer (mtime/mtimecmp)
//   - System Control (hart ID, boot addr, scratch)
//
// The instruction port reads directly from ROM (for boot) or RAM.
// The data port goes through the bus interconnect to all slaves.
//
// For multi-core, this module is replaced by the AXI-based top.
//============================================================================

module riscv_soc_top
    import soc_pkg::*;
#(
    parameter int    HART_ID       = 0,
    parameter int    NUM_HARTS     = 1,
    parameter        ROM_INIT_FILE = "",
    parameter        RAM_INIT_FILE = ""
)(
    input  logic        clk,
    input  logic        rst_n,

    // External UART
    output logic        uart_tx,
    input  logic        uart_rx,

    // Interrupts (directly from peripherals for now)
    output logic        irq_timer,
    output logic        irq_uart_tx
);

    // -----------------------------------------------------------------------
    // Core signals
    // -----------------------------------------------------------------------
    logic [31:0] imem_addr, imem_rdata;
    logic        imem_req, imem_valid;

    logic [31:0] dmem_addr, dmem_wdata, dmem_rdata;
    logic        dmem_rd, dmem_wr;
    logic [3:0]  dmem_be;
    logic        dmem_valid;

    // -----------------------------------------------------------------------
    // Core instance
    // -----------------------------------------------------------------------
    rv32i_core #(
        .HART_ID   (HART_ID),
        .RESET_PC  (ROM_BASE)
    ) u_core (
        .clk        (clk),
        .rst_n      (rst_n),
        .imem_addr  (imem_addr),
        .imem_rdata (imem_rdata),
        .imem_req   (imem_req),
        .imem_valid (imem_valid),
        .dmem_addr  (dmem_addr),
        .dmem_wdata (dmem_wdata),
        .dmem_rdata (dmem_rdata),
        .dmem_rd    (dmem_rd),
        .dmem_wr    (dmem_wr),
        .dmem_be    (dmem_be),
        .dmem_valid (dmem_valid)
    );

    // -----------------------------------------------------------------------
    // Instruction memory: ROM + RAM dual path
    //
    // The instruction port can fetch from ROM (boot code) or RAM
    // (after a jump to RAM). We use a simple address-based mux.
    // -----------------------------------------------------------------------
    logic [31:0] rom_imem_rdata, ram_imem_rdata;
    logic        rom_imem_valid, ram_imem_valid;
    logic        imem_sel_ram;

    // Determine if instruction fetch targets RAM region
    assign imem_sel_ram = (imem_addr >= RAM_BASE) &&
                          (imem_addr < (RAM_BASE + RAM_SIZE));

    // Instruction-side ROM read (separate from data-side ROM)
    logic [31:0] rom_i_addr;
    logic        rom_i_rd;

    assign rom_i_addr = {20'b0, imem_addr[13:0]};
    assign rom_i_rd   = imem_req && !imem_sel_ram;

    boot_rom #(
        .DEPTH         (4096),
        .MEM_INIT_FILE (ROM_INIT_FILE)
    ) u_boot_rom (
        .clk   (clk),
        .rst_n (rst_n),
        .addr  (rom_i_addr),
        .rd_en (rom_i_rd),
        .rdata (rom_imem_rdata),
        .valid (rom_imem_valid)
    );

    // Instruction-side RAM read (separate read port)
    // We instantiate a second read-only port into the same RAM conceptually.
    // For simplicity, we use a separate small ROM-like interface to the SRAM.
    // In a real design, you'd have a dual-port SRAM. Here we create a
    // dedicated read port.
    logic [31:0] ram_i_rdata;
    logic        ram_i_valid;

    // Simple instruction-side RAM: just read the same memory
    // For now, use a combinational read with registered output
    // (The data-side SRAM handles writes; instruction-side is read-only)

    // Instruction mux
    assign imem_rdata = imem_sel_ram ? ram_i_rdata : rom_imem_rdata;
    assign imem_valid = imem_sel_ram ? ram_i_valid : rom_imem_valid;

    // -----------------------------------------------------------------------
    // Slave signals from bus interconnect
    // -----------------------------------------------------------------------
    logic [31:0] bus_rom_addr,     bus_rom_rdata;
    logic        bus_rom_rd,       bus_rom_valid;

    logic [31:0] bus_ram_addr,     bus_ram_wdata, bus_ram_rdata;
    logic        bus_ram_rd,       bus_ram_wr,    bus_ram_valid;
    logic [3:0]  bus_ram_be;

    logic [31:0] bus_uart_addr,    bus_uart_wdata, bus_uart_rdata;
    logic        bus_uart_rd,      bus_uart_wr,    bus_uart_valid;
    logic [3:0]  bus_uart_be;

    logic [31:0] bus_timer_addr,   bus_timer_wdata, bus_timer_rdata;
    logic        bus_timer_rd,     bus_timer_wr,    bus_timer_valid;
    logic [3:0]  bus_timer_be;

    logic [31:0] bus_sysctrl_addr, bus_sysctrl_wdata, bus_sysctrl_rdata;
    logic        bus_sysctrl_rd,   bus_sysctrl_wr,    bus_sysctrl_valid;
    logic [3:0]  bus_sysctrl_be;

    // -----------------------------------------------------------------------
    // Bus Interconnect
    // -----------------------------------------------------------------------
    bus_interconnect u_bus (
        .clk           (clk),
        .rst_n         (rst_n),

        .master_addr   (dmem_addr),
        .master_wdata  (dmem_wdata),
        .master_rd     (dmem_rd),
        .master_wr     (dmem_wr),
        .master_be     (dmem_be),
        .master_rdata  (dmem_rdata),
        .master_valid  (dmem_valid),

        .rom_addr      (bus_rom_addr),
        .rom_rd        (bus_rom_rd),
        .rom_rdata     (bus_rom_rdata),
        .rom_valid     (bus_rom_valid),

        .ram_addr      (bus_ram_addr),
        .ram_wdata     (bus_ram_wdata),
        .ram_rd        (bus_ram_rd),
        .ram_wr        (bus_ram_wr),
        .ram_be        (bus_ram_be),
        .ram_rdata     (bus_ram_rdata),
        .ram_valid     (bus_ram_valid),

        .uart_addr     (bus_uart_addr),
        .uart_wdata    (bus_uart_wdata),
        .uart_rd       (bus_uart_rd),
        .uart_wr       (bus_uart_wr),
        .uart_be       (bus_uart_be),
        .uart_rdata    (bus_uart_rdata),
        .uart_valid    (bus_uart_valid),

        .timer_addr    (bus_timer_addr),
        .timer_wdata   (bus_timer_wdata),
        .timer_rd      (bus_timer_rd),
        .timer_wr      (bus_timer_wr),
        .timer_be      (bus_timer_be),
        .timer_rdata   (bus_timer_rdata),
        .timer_valid   (bus_timer_valid),

        .sysctrl_addr  (bus_sysctrl_addr),
        .sysctrl_wdata (bus_sysctrl_wdata),
        .sysctrl_rd    (bus_sysctrl_rd),
        .sysctrl_wr    (bus_sysctrl_wr),
        .sysctrl_be    (bus_sysctrl_be),
        .sysctrl_rdata (bus_sysctrl_rdata),
        .sysctrl_valid (bus_sysctrl_valid)
    );

    // -----------------------------------------------------------------------
    // Data-side ROM (read-only access via data bus for constants, etc.)
    // Uses a separate instance from the instruction-side ROM.
    // Both read the same initial contents.
    // -----------------------------------------------------------------------
    boot_rom #(
        .DEPTH         (4096),
        .MEM_INIT_FILE (ROM_INIT_FILE)
    ) u_data_rom (
        .clk   (clk),
        .rst_n (rst_n),
        .addr  (bus_rom_addr),
        .rd_en (bus_rom_rd),
        .rdata (bus_rom_rdata),
        .valid (bus_rom_valid)
    );

    // -----------------------------------------------------------------------
    // Main SRAM — dual use: data port (R/W) + instruction port (R only)
    //
    // We handle this by giving priority to data writes and time-sharing.
    // For simplicity in this single-core design, we use the SRAM for data
    // and a separate read path for instructions. A proper dual-port SRAM
    // would be used in synthesis.
    // -----------------------------------------------------------------------
    sram #(
        .DEPTH         (16384),
        .MEM_INIT_FILE (RAM_INIT_FILE)
    ) u_main_ram (
        .clk   (clk),
        .rst_n (rst_n),
        .addr  (bus_ram_addr),
        .wdata (bus_ram_wdata),
        .rd_en (bus_ram_rd),
        .wr_en (bus_ram_wr),
        .be    (bus_ram_be),
        .rdata (bus_ram_rdata),
        .valid (bus_ram_valid)
    );

    // Instruction-side RAM read (read-only port)
    // In a real design this would be port B of a true dual-port SRAM.
    // For simulation, we use a second SRAM instance (not ideal for writes,
    // but works for read-only instruction fetch from pre-loaded content).
    sram #(
        .DEPTH         (16384),
        .MEM_INIT_FILE (RAM_INIT_FILE)
    ) u_iram (
        .clk   (clk),
        .rst_n (rst_n),
        .addr  ({16'b0, imem_addr[15:0]}),
        .wdata ('0),
        .rd_en (imem_req && imem_sel_ram),
        .wr_en (1'b0),
        .be    (4'b0),
        .rdata (ram_i_rdata),
        .valid (ram_i_valid)
    );

    // -----------------------------------------------------------------------
    // UART
    // -----------------------------------------------------------------------
    uart #(
        .DEFAULT_BAUD_DIV (868)
    ) u_uart (
        .clk         (clk),
        .rst_n       (rst_n),
        .addr        (bus_uart_addr),
        .wdata       (bus_uart_wdata),
        .rd_en       (bus_uart_rd),
        .wr_en       (bus_uart_wr),
        .be          (bus_uart_be),
        .rdata       (bus_uart_rdata),
        .valid       (bus_uart_valid),
        .uart_tx     (uart_tx),
        .uart_rx     (uart_rx),
        .irq_tx_done (irq_uart_tx)
    );

    // -----------------------------------------------------------------------
    // Timer
    // -----------------------------------------------------------------------
    timer u_timer (
        .clk       (clk),
        .rst_n     (rst_n),
        .addr      (bus_timer_addr),
        .wdata     (bus_timer_wdata),
        .rd_en     (bus_timer_rd),
        .wr_en     (bus_timer_wr),
        .be        (bus_timer_be),
        .rdata     (bus_timer_rdata),
        .valid     (bus_timer_valid),
        .irq_timer (irq_timer)
    );

    // -----------------------------------------------------------------------
    // System Control
    // -----------------------------------------------------------------------
    sys_ctrl #(
        .HART_ID           (HART_ID),
        .NUM_HARTS         (NUM_HARTS),
        .DEFAULT_BOOT_ADDR (ROM_BASE)
    ) u_sysctrl (
        .clk   (clk),
        .rst_n (rst_n),
        .addr  (bus_sysctrl_addr),
        .wdata (bus_sysctrl_wdata),
        .rd_en (bus_sysctrl_rd),
        .wr_en (bus_sysctrl_wr),
        .be    (bus_sysctrl_be),
        .rdata (bus_sysctrl_rdata),
        .valid (bus_sysctrl_valid)
    );

endmodule