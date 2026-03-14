`timescale 1ns / 1ps
module tb_mesh_final;
    import noc_pkg::*;
    logic clk, rst_n;
    initial clk = 0;
    always #5 clk = ~clk;

    logic [31:0] c_addr, c_wdata, c_rdata; logic c_rd, c_wr, c_valid; logic [3:0] c_be;
    logic [31:0] aw_a, w_d, ar_a, r_d; logic [2:0] aw_p, ar_p; logic [3:0] w_s;
    logic aw_v,aw_r,w_v,w_r; logic [1:0] b_re,r_re;
    logic b_v,b_r,ar_v,ar_r,r_v,r_r;
    logic [FLIT_W-1:0] n_od, n_id; logic n_ov, n_or, n_iv, n_ir;

    axi_lite_master u_m(.clk(clk),.rst_n(rst_n),.core_addr(c_addr),.core_wdata(c_wdata),.core_rd(c_rd),.core_wr(c_wr),.core_be(c_be),.core_rdata(c_rdata),.core_valid(c_valid),.m_axi_awaddr(aw_a),.m_axi_awprot(aw_p),.m_axi_awvalid(aw_v),.m_axi_awready(aw_r),.m_axi_wdata(w_d),.m_axi_wstrb(w_s),.m_axi_wvalid(w_v),.m_axi_wready(w_r),.m_axi_bresp(b_re),.m_axi_bvalid(b_v),.m_axi_bready(b_r),.m_axi_araddr(ar_a),.m_axi_arprot(ar_p),.m_axi_arvalid(ar_v),.m_axi_arready(ar_r),.m_axi_rdata(r_d),.m_axi_rresp(r_re),.m_axi_rvalid(r_v),.m_axi_rready(r_r));

    axi_noc_bridge #(.MY_X(0),.MY_Y(0)) u_nb(.clk(clk),.rst_n(rst_n),.s_axi_awaddr(aw_a),.s_axi_awprot(aw_p),.s_axi_awvalid(aw_v),.s_axi_awready(aw_r),.s_axi_wdata(w_d),.s_axi_wstrb(w_s),.s_axi_wvalid(w_v),.s_axi_wready(w_r),.s_axi_bresp(b_re),.s_axi_bvalid(b_v),.s_axi_bready(b_r),.s_axi_araddr(ar_a),.s_axi_arprot(ar_p),.s_axi_arvalid(ar_v),.s_axi_arready(ar_r),.s_axi_rdata(r_d),.s_axi_rresp(r_re),.s_axi_rvalid(r_v),.s_axi_rready(r_r),.noc_out_data(n_od),.noc_out_valid(n_ov),.noc_out_ready(n_or),.noc_in_data(n_id),.noc_in_valid(n_iv),.noc_in_ready(n_ir));

    logic [FLIT_W-1:0] sb_od, sb_id; logic sb_ov, sb_or, sb_iv, sb_ir;
    logic [31:0] p_addr, p_wdata, p_rdata; logic p_rd, p_wr, p_valid; logic [3:0] p_be;

    noc_slave_bridge u_sb(.clk(clk),.rst_n(rst_n),.noc_in_data(sb_id),.noc_in_valid(sb_iv),.noc_in_ready(sb_ir),.noc_out_data(sb_od),.noc_out_valid(sb_ov),.noc_out_ready(sb_or),.periph_addr(p_addr),.periph_wdata(p_wdata),.periph_rd(p_rd),.periph_wr(p_wr),.periph_be(p_be),.periph_rdata(p_rdata),.periph_valid(p_valid));

    logic [31:0] ram[0:15]; initial for(int i=0;i<16;i++) ram[i]=0;
    always_ff @(posedge clk) if(p_wr) ram[p_addr[5:2]]<=p_wdata;
    assign p_rdata=ram[p_addr[5:2]]; assign p_valid=p_rd||p_wr;

    // Mesh — T0=master, T1=slave, T2/T3=unused
    logic [FLIT_W-1:0] ml_id[0:3], ml_od[0:3]; logic ml_iv[0:3],ml_ir[0:3],ml_ov[0:3],ml_or[0:3];
    assign ml_id[0]=n_od; assign ml_iv[0]=n_ov; assign n_or=ml_ir[0];
    assign n_id=ml_od[0]; assign n_iv=ml_ov[0]; assign ml_or[0]=n_ir;
    assign ml_id[1]=sb_od; assign ml_iv[1]=sb_ov; assign sb_or=ml_ir[1];
    assign sb_id=ml_od[1]; assign sb_iv=ml_ov[1]; assign ml_or[1]=sb_ir;
    assign ml_id[2]='0; assign ml_iv[2]=0; assign ml_or[2]=1;
    assign ml_id[3]='0; assign ml_iv[3]=0; assign ml_or[3]=1;

    mesh_2x2 #(.FIFO_DEPTH(2)) u_mesh(.clk(clk),.rst_n(rst_n),
        .t0_local_in_data(ml_id[0]),.t0_local_in_valid(ml_iv[0]),.t0_local_in_ready(ml_ir[0]),
        .t0_local_out_data(ml_od[0]),.t0_local_out_valid(ml_ov[0]),.t0_local_out_ready(ml_or[0]),
        .t1_local_in_data(ml_id[1]),.t1_local_in_valid(ml_iv[1]),.t1_local_in_ready(ml_ir[1]),
        .t1_local_out_data(ml_od[1]),.t1_local_out_valid(ml_ov[1]),.t1_local_out_ready(ml_or[1]),
        .t2_local_in_data(ml_id[2]),.t2_local_in_valid(ml_iv[2]),.t2_local_in_ready(ml_ir[2]),
        .t2_local_out_data(ml_od[2]),.t2_local_out_valid(ml_ov[2]),.t2_local_out_ready(ml_or[2]),
        .t3_local_in_data(ml_id[3]),.t3_local_in_valid(ml_iv[3]),.t3_local_in_ready(ml_ir[3]),
        .t3_local_out_data(ml_od[3]),.t3_local_out_valid(ml_ov[3]),.t3_local_out_ready(ml_or[3]));

    integer pc, fc; logic [31:0] rd;
    task automatic check(input string n, input logic[31:0] g, e);
        if(g===e) begin $display("[PASS] %s: 0x%08h",n,g); pc++; end
        else begin $display("[FAIL] %s: got 0x%08h exp 0x%08h",n,g,e); fc++; end
    endtask

    initial begin
        pc=0; fc=0; c_addr=0; c_wdata=0; c_rd=0; c_wr=0; c_be=0;
        rst_n=0; #50; rst_n=1; #20;
        $display("\n=== 2x2 Mesh NoC Tests ===");

        // Write via mesh: T0→T1 (East hop)
        @(posedge clk); c_addr<=32'h8000_0000; c_wdata<=32'hDEAD_BEEF; c_be<=4'hF; c_wr<=1;
        @(posedge clk); c_wr<=0; @(posedge clk);
        begin:w1 for(int t=0;t<100;t++) begin if(c_valid) disable w1; @(posedge clk); end $display("TIMEOUT w1"); end
        #40;

        // Read via mesh: T0→T1 (East hop)
        @(posedge clk); c_addr<=32'h8000_0000; c_rd<=1; c_be<=4'hF;
        @(posedge clk); c_rd<=0; @(posedge clk);
        begin:r1 for(int t=0;t<100;t++) begin if(c_valid) begin rd=c_rdata; disable r1; end @(posedge clk); end rd=32'hDEAD; end
        check("T0→T1 East W/R", rd, 32'hDEAD_BEEF);
        #40;

        // Second write at different address
        @(posedge clk); c_addr<=32'h8000_0004; c_wdata<=32'hCAFE_BABE; c_be<=4'hF; c_wr<=1;
        @(posedge clk); c_wr<=0; @(posedge clk);
        begin:w2 for(int t=0;t<100;t++) begin if(c_valid) disable w2; @(posedge clk); end $display("TIMEOUT w2"); end
        #40;

        // Read back both
        @(posedge clk); c_addr<=32'h8000_0004; c_rd<=1; c_be<=4'hF;
        @(posedge clk); c_rd<=0; @(posedge clk);
        begin:r2 for(int t=0;t<100;t++) begin if(c_valid) begin rd=c_rdata; disable r2; end @(posedge clk); end rd=32'hDEAD; end
        check("Second W/R", rd, 32'hCAFE_BABE);
        #20;
        @(posedge clk); c_addr<=32'h8000_0000; c_rd<=1; c_be<=4'hF;
        @(posedge clk); c_rd<=0; @(posedge clk);
        begin:r3 for(int t=0;t<100;t++) begin if(c_valid) begin rd=c_rdata; disable r3; end @(posedge clk); end rd=32'hDEAD; end
        check("First persist", rd, 32'hDEAD_BEEF);

        $display("\n=== %0d pass, %0d fail ===", pc, fc);
        if(fc==0) $display("*** ALL MESH NOC TESTS PASSED ***\n");
        $finish;
    end
endmodule