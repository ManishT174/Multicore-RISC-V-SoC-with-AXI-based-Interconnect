//============================================================================
// tb_axi_xbar.sv — AXI-Lite Crossbar Testbench
//============================================================================
`timescale 1ns / 1ps

module tb_axi_xbar;

    logic clk, rst_n;
    initial clk = 0;
    always #5 clk = ~clk;

    // ---- Core-side simple interfaces (2 masters) ----
    logic [31:0] c_addr  [0:1], c_wdata [0:1], c_rdata [0:1];
    logic        c_rd    [0:1], c_wr    [0:1], c_valid [0:1];
    logic [3:0]  c_be    [0:1];

    // ---- AXI wires: master bridge ↔ crossbar (per-master) ----
    logic [31:0] ma_awaddr[0:1], ma_wdata[0:1], ma_araddr[0:1], ma_rdata[0:1];
    logic [2:0]  ma_awprot[0:1], ma_arprot[0:1];
    logic [3:0]  ma_wstrb [0:1];
    logic        ma_awvalid[0:1],ma_awready[0:1],ma_wvalid[0:1],ma_wready[0:1];
    logic [1:0]  ma_bresp [0:1], ma_rresp[0:1];
    logic        ma_bvalid[0:1], ma_bready[0:1];
    logic        ma_arvalid[0:1],ma_arready[0:1],ma_rvalid[0:1],ma_rready[0:1];

    // ---- AXI wires: crossbar ↔ slave bridge (per slave, 5 slaves) ----
    logic [31:0] sa_awaddr[0:4], sa_wdata[0:4], sa_araddr[0:4], sa_rdata[0:4];
    logic [2:0]  sa_awprot[0:4], sa_arprot[0:4];
    logic [3:0]  sa_wstrb [0:4];
    logic        sa_awvalid[0:4],sa_awready[0:4],sa_wvalid[0:4],sa_wready[0:4];
    logic [1:0]  sa_bresp [0:4], sa_rresp[0:4];
    logic        sa_bvalid[0:4], sa_bready[0:4];
    logic        sa_arvalid[0:4],sa_arready[0:4],sa_rvalid[0:4],sa_rready[0:4];

    // ---- Peripheral bus from slave bridges ----
    logic [31:0] p_addr[0:4], p_wdata[0:4], p_rdata[0:4];
    logic        p_rd[0:4], p_wr[0:4], p_valid[0:4];
    logic [3:0]  p_be[0:4];

    // -----------------------------------------------------------------------
    // Master bridges (only 2 active; tie off m2/m3 at crossbar)
    // -----------------------------------------------------------------------
    generate
        for (genvar mi = 0; mi < 2; mi++) begin : gen_mbridge
            axi_lite_master u_mbridge (
                .clk(clk), .rst_n(rst_n),
                .core_addr(c_addr[mi]), .core_wdata(c_wdata[mi]),
                .core_rd(c_rd[mi]), .core_wr(c_wr[mi]), .core_be(c_be[mi]),
                .core_rdata(c_rdata[mi]), .core_valid(c_valid[mi]),
                .m_axi_awaddr(ma_awaddr[mi]), .m_axi_awprot(ma_awprot[mi]),
                .m_axi_awvalid(ma_awvalid[mi]), .m_axi_awready(ma_awready[mi]),
                .m_axi_wdata(ma_wdata[mi]), .m_axi_wstrb(ma_wstrb[mi]),
                .m_axi_wvalid(ma_wvalid[mi]), .m_axi_wready(ma_wready[mi]),
                .m_axi_bresp(ma_bresp[mi]), .m_axi_bvalid(ma_bvalid[mi]),
                .m_axi_bready(ma_bready[mi]),
                .m_axi_araddr(ma_araddr[mi]), .m_axi_arprot(ma_arprot[mi]),
                .m_axi_arvalid(ma_arvalid[mi]), .m_axi_arready(ma_arready[mi]),
                .m_axi_rdata(ma_rdata[mi]), .m_axi_rresp(ma_rresp[mi]),
                .m_axi_rvalid(ma_rvalid[mi]), .m_axi_rready(ma_rready[mi])
            );
        end
    endgenerate

    // -----------------------------------------------------------------------
    // Crossbar (4M x 5S — m2/m3 tied off)
    // -----------------------------------------------------------------------
    axi_lite_xbar #(.NUM_MASTERS(4), .NUM_SLAVES(5)) u_xbar (
        .clk(clk), .rst_n(rst_n),
        // M0
        .m0_awaddr(ma_awaddr[0]), .m0_awprot(ma_awprot[0]),
        .m0_awvalid(ma_awvalid[0]), .m0_awready(ma_awready[0]),
        .m0_wdata(ma_wdata[0]), .m0_wstrb(ma_wstrb[0]),
        .m0_wvalid(ma_wvalid[0]), .m0_wready(ma_wready[0]),
        .m0_bresp(ma_bresp[0]), .m0_bvalid(ma_bvalid[0]), .m0_bready(ma_bready[0]),
        .m0_araddr(ma_araddr[0]), .m0_arprot(ma_arprot[0]),
        .m0_arvalid(ma_arvalid[0]), .m0_arready(ma_arready[0]),
        .m0_rdata(ma_rdata[0]), .m0_rresp(ma_rresp[0]),
        .m0_rvalid(ma_rvalid[0]), .m0_rready(ma_rready[0]),
        // M1
        .m1_awaddr(ma_awaddr[1]), .m1_awprot(ma_awprot[1]),
        .m1_awvalid(ma_awvalid[1]), .m1_awready(ma_awready[1]),
        .m1_wdata(ma_wdata[1]), .m1_wstrb(ma_wstrb[1]),
        .m1_wvalid(ma_wvalid[1]), .m1_wready(ma_wready[1]),
        .m1_bresp(ma_bresp[1]), .m1_bvalid(ma_bvalid[1]), .m1_bready(ma_bready[1]),
        .m1_araddr(ma_araddr[1]), .m1_arprot(ma_arprot[1]),
        .m1_arvalid(ma_arvalid[1]), .m1_arready(ma_arready[1]),
        .m1_rdata(ma_rdata[1]), .m1_rresp(ma_rresp[1]),
        .m1_rvalid(ma_rvalid[1]), .m1_rready(ma_rready[1]),
        // M2 (tied off)
        .m2_awaddr(32'h0), .m2_awprot(3'h0), .m2_awvalid(1'b0), .m2_awready(),
        .m2_wdata(32'h0), .m2_wstrb(4'h0), .m2_wvalid(1'b0), .m2_wready(),
        .m2_bresp(), .m2_bvalid(), .m2_bready(1'b0),
        .m2_araddr(32'h0), .m2_arprot(3'h0), .m2_arvalid(1'b0), .m2_arready(),
        .m2_rdata(), .m2_rresp(), .m2_rvalid(), .m2_rready(1'b0),
        // M3 (tied off)
        .m3_awaddr(32'h0), .m3_awprot(3'h0), .m3_awvalid(1'b0), .m3_awready(),
        .m3_wdata(32'h0), .m3_wstrb(4'h0), .m3_wvalid(1'b0), .m3_wready(),
        .m3_bresp(), .m3_bvalid(), .m3_bready(1'b0),
        .m3_araddr(32'h0), .m3_arprot(3'h0), .m3_arvalid(1'b0), .m3_arready(),
        .m3_rdata(), .m3_rresp(), .m3_rvalid(), .m3_rready(1'b0),
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

    // -----------------------------------------------------------------------
    // Slave bridges
    // -----------------------------------------------------------------------
    generate
        for (genvar si = 0; si < 5; si++) begin : gen_sbridge
            axi_lite_slave u_sbridge (
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

    // -----------------------------------------------------------------------
    // Simple memory models
    // -----------------------------------------------------------------------
    // S0 (ROM): echo address
    assign p_rdata[0] = p_addr[0];
    assign p_valid[0] = p_rd[0];

    // S1 (RAM): 256 words
    logic [31:0] test_ram [0:255];
    wire [7:0] ridx = p_addr[1][9:2];
    always_ff @(posedge clk) begin
        if (p_wr[1]) begin
            if (p_be[1][0]) test_ram[ridx][7:0]   <= p_wdata[1][7:0];
            if (p_be[1][1]) test_ram[ridx][15:8]  <= p_wdata[1][15:8];
            if (p_be[1][2]) test_ram[ridx][23:16] <= p_wdata[1][23:16];
            if (p_be[1][3]) test_ram[ridx][31:24] <= p_wdata[1][31:24];
        end
    end
    assign p_rdata[1] = test_ram[ridx];
    assign p_valid[1] = p_rd[1] || p_wr[1];

    // S2-S4: constant returns
    assign p_rdata[2] = 32'h0A170000; assign p_valid[2] = p_rd[2];
    assign p_rdata[3] = 32'h71BE0000; assign p_valid[3] = p_rd[3];
    assign p_rdata[4] = 32'h5C5C0000; assign p_valid[4] = p_rd[4];

    initial for (int i = 0; i < 256; i++) test_ram[i] = 0;

    // -----------------------------------------------------------------------
    // Test tasks
    // -----------------------------------------------------------------------
    task automatic do_write(input int mi, input logic [31:0] addr,
                            input logic [31:0] data, input logic [3:0] be);
        @(posedge clk);
        c_addr[mi]  <= addr;  c_wdata[mi] <= data;
        c_be[mi]    <= be;    c_wr[mi]    <= 1'b1;  c_rd[mi] <= 1'b0;
        @(posedge clk);
        c_wr[mi] <= 1'b0;
        while (!c_valid[mi]) @(posedge clk);
    endtask

    task automatic do_read(input int mi, input logic [31:0] addr,
                           output logic [31:0] data);
        @(posedge clk);
        c_addr[mi] <= addr;  c_rd[mi] <= 1'b1;  c_wr[mi] <= 1'b0;
        c_be[mi]   <= 4'hF;
        @(posedge clk);
        c_rd[mi] <= 1'b0;
        while (!c_valid[mi]) @(posedge clk);
        data = c_rdata[mi];
    endtask

    integer pass_count, fail_count;
    logic [31:0] rd_tmp;

    task automatic check(input string name, input logic [31:0] got,
                         input logic [31:0] exp);
        if (got === exp) begin
            $display("[PASS] %s: 0x%08h", name, got);
            pass_count++;
        end else begin
            $display("[FAIL] %s: got 0x%08h exp 0x%08h", name, got, exp);
            fail_count++;
        end
    endtask

    initial begin
        $dumpfile("axi_xbar_tb.vcd");
        $dumpvars(0, tb_axi_xbar);
        pass_count = 0; fail_count = 0;

        for (int i = 0; i < 2; i++) begin
            c_addr[i] = 0; c_wdata[i] = 0;
            c_rd[i] = 0; c_wr[i] = 0; c_be[i] = 0;
        end

        rst_n = 0; #50; rst_n = 1; #20;

        $display("\n========================================");
        $display(" AXI-Lite Crossbar Tests");
        $display("========================================");

        // Test 1: M0 write/read RAM
        $display("\n--- Test 1: M0 write/read RAM ---");
        do_write(0, 32'h8000_0000, 32'hDEAD_BEEF, 4'hF);
        #20;
        do_read(0, 32'h8000_0000, rd_tmp);
        check("M0 RAM W/R", rd_tmp, 32'hDEAD_BEEF);
        #40;

        // Test 2: M1 write/read RAM (different address)
        $display("\n--- Test 2: M1 write/read RAM ---");
        do_write(1, 32'h8000_0010, 32'hCAFE_1234, 4'hF);
        #20;
        do_read(1, 32'h8000_0010, rd_tmp);
        check("M1 RAM W/R", rd_tmp, 32'hCAFE_1234);
        #40;

        // Test 3: M0 read ROM (address echo)
        $display("\n--- Test 3: M0 read ROM ---");
        do_read(0, 32'h0000_0100, rd_tmp);
        check("M0 ROM read", rd_tmp, 32'h0000_0100);
        #40;

        // Test 4: M1 read SYSCTRL
        $display("\n--- Test 4: M1 read SYSCTRL ---");
        do_read(1, 32'hF002_0000, rd_tmp);
        check("M1 SYSCTRL", rd_tmp, 32'h5C5C0000);
        #40;

        // Test 5: M0 re-read RAM (persistence)
        $display("\n--- Test 5: M0 re-read RAM ---");
        do_read(0, 32'h8000_0000, rd_tmp);
        check("M0 RAM persist", rd_tmp, 32'hDEAD_BEEF);
        #40;

        // Test 6: Byte-enable write
        $display("\n--- Test 6: Byte-enable write ---");
        do_write(0, 32'h8000_0020, 32'hAABBCCDD, 4'hF);
        #20;
        do_write(0, 32'h8000_0020, 32'h00FF0000, 4'b0100);
        #20;
        do_read(0, 32'h8000_0020, rd_tmp);
        check("Byte-enable", rd_tmp, 32'hAAFF_CCDD);

        $display("\n========================================");
        $display(" %0d passed, %0d failed", pass_count, fail_count);
        $display("========================================");
        if (fail_count == 0)
            $display("\n*** ALL AXI TESTS PASSED ***\n");
        else
            $display("\n*** SOME AXI TESTS FAILED ***\n");
        $finish;
    end

endmodule