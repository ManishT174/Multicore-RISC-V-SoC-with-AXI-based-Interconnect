//============================================================================
// mesh_router.sv — 2D Mesh NoC Router with XY Routing (Icarus-safe)
//
// All per-port logic fully unrolled — no dynamic array indexing
// inside always_comb blocks (Icarus limitation).
//============================================================================

module mesh_router
    import noc_pkg::*;
#(
    parameter int MY_X       = 0,
    parameter int MY_Y       = 0,
    parameter int FIFO_DEPTH = 4
)(
    input  logic clk, rst_n,

    input  logic [FLIT_W-1:0] local_in_data,  input  logic local_in_valid,  output logic local_in_ready,
    output logic [FLIT_W-1:0] local_out_data,  output logic local_out_valid, input  logic local_out_ready,

    input  logic [FLIT_W-1:0] north_in_data,  input  logic north_in_valid,  output logic north_in_ready,
    output logic [FLIT_W-1:0] north_out_data,  output logic north_out_valid, input  logic north_out_ready,

    input  logic [FLIT_W-1:0] south_in_data,  input  logic south_in_valid,  output logic south_in_ready,
    output logic [FLIT_W-1:0] south_out_data,  output logic south_out_valid, input  logic south_out_ready,

    input  logic [FLIT_W-1:0] east_in_data,   input  logic east_in_valid,   output logic east_in_ready,
    output logic [FLIT_W-1:0] east_out_data,   output logic east_out_valid,  input  logic east_out_ready,

    input  logic [FLIT_W-1:0] west_in_data,   input  logic west_in_valid,   output logic west_in_ready,
    output logic [FLIT_W-1:0] west_out_data,   output logic west_out_valid,  input  logic west_out_ready
);

    // ---- Input FIFOs ----
    logic [FLIT_W-1:0] fd [0:4]; // fifo_dout
    logic               fv [0:4]; // fifo_valid
    logic               fr [0:4]; // fifo_ready (pop)

    logic [FLIT_W-1:0] pi_d [0:4];
    logic               pi_v [0:4];
    logic               pi_r [0:4];

    assign pi_d[0]=local_in_data; assign pi_v[0]=local_in_valid; assign local_in_ready=pi_r[0];
    assign pi_d[1]=north_in_data; assign pi_v[1]=north_in_valid; assign north_in_ready=pi_r[1];
    assign pi_d[2]=south_in_data; assign pi_v[2]=south_in_valid; assign south_in_ready=pi_r[2];
    assign pi_d[3]=east_in_data;  assign pi_v[3]=east_in_valid;  assign east_in_ready =pi_r[3];
    assign pi_d[4]=west_in_data;  assign pi_v[4]=west_in_valid;  assign west_in_ready =pi_r[4];

    generate
        for (genvar p = 0; p < 5; p++) begin : gf
            noc_fifo #(.WIDTH(FLIT_W), .DEPTH(FIFO_DEPTH)) u_fifo (
                .clk(clk), .rst_n(rst_n),
                .din(pi_d[p]), .din_valid(pi_v[p]), .din_ready(pi_r[p]),
                .dout(fd[p]),  .dout_valid(fv[p]),  .dout_ready(fr[p])
            );
        end
    endgenerate

    // ---- XY Route: per-port, fully unrolled ----
    logic [2:0] rp [0:4]; // route_port

    // Macro: XY route for input port P using flit bits [122]=dst_x, [121]=dst_y
    `define DO_ROUTE(P) \
        always_comb begin \
            if      (fd[P][122] > MY_X[0]) rp[P] = 3'd3; /* EAST  */ \
            else if (fd[P][122] < MY_X[0]) rp[P] = 3'd4; /* WEST  */ \
            else if (fd[P][121] > MY_Y[0]) rp[P] = 3'd1; /* NORTH */ \
            else if (fd[P][121] < MY_Y[0]) rp[P] = 3'd2; /* SOUTH */ \
            else                           rp[P] = 3'd0; /* LOCAL */ \
        end

    `DO_ROUTE(0)
    `DO_ROUTE(1)
    `DO_ROUTE(2)
    `DO_ROUTE(3)
    `DO_ROUTE(4)

    // ---- Arbiter request matrix: req[outport] = {ip4,ip3,ip2,ip1,ip0} ----
    logic [4:0] arb_req [0:4];

    // Unrolled: arb_req[op][ip] = fv[ip] && (rp[ip] == op)
    `define ARB_REQ_BIT(OP, IP) (fv[IP] && (rp[IP] == 3'd``OP``))

    always_comb begin
        arb_req[0] = {`ARB_REQ_BIT(0,4), `ARB_REQ_BIT(0,3), `ARB_REQ_BIT(0,2), `ARB_REQ_BIT(0,1), `ARB_REQ_BIT(0,0)};
        arb_req[1] = {`ARB_REQ_BIT(1,4), `ARB_REQ_BIT(1,3), `ARB_REQ_BIT(1,2), `ARB_REQ_BIT(1,1), `ARB_REQ_BIT(1,0)};
        arb_req[2] = {`ARB_REQ_BIT(2,4), `ARB_REQ_BIT(2,3), `ARB_REQ_BIT(2,2), `ARB_REQ_BIT(2,1), `ARB_REQ_BIT(2,0)};
        arb_req[3] = {`ARB_REQ_BIT(3,4), `ARB_REQ_BIT(3,3), `ARB_REQ_BIT(3,2), `ARB_REQ_BIT(3,1), `ARB_REQ_BIT(3,0)};
        arb_req[4] = {`ARB_REQ_BIT(4,4), `ARB_REQ_BIT(4,3), `ARB_REQ_BIT(4,2), `ARB_REQ_BIT(4,1), `ARB_REQ_BIT(4,0)};
    end

    // ---- Per-output-port RR arbiters ----
    logic [4:0] arb_g [0:4];
    logic        arb_gv[0:4];
    logic [2:0]  arb_gi[0:4];

    generate
        for (genvar op = 0; op < 5; op++) begin : ga
            rr_arbiter #(.N(5)) u_arb (
                .clk(clk), .rst_n(rst_n),
                .req(arb_req[op]), .grant(arb_g[op]),
                .grant_valid(arb_gv[op]), .grant_idx(arb_gi[op][$clog2(5)-1:0])
            );
        end
    endgenerate

    // ---- Output ready ----
    wire or0 = local_out_ready, or1 = north_out_ready, or2 = south_out_ready;
    wire or3 = east_out_ready,  or4 = west_out_ready;

    // ---- Output mux: per output port, select winning input's flit ----
    // Fully unrolled per output port
    logic [FLIT_W-1:0] od [0:4];
    logic               ov [0:4];

    `define OUT_MUX(OP, OR) \
        always_comb begin \
            od[OP] = '0; \
            ov[OP] = 1'b0; \
            if (arb_gv[OP] && OR) begin \
                if (arb_g[OP][0]) begin od[OP] = fd[0]; ov[OP] = 1'b1; end \
                if (arb_g[OP][1]) begin od[OP] = fd[1]; ov[OP] = 1'b1; end \
                if (arb_g[OP][2]) begin od[OP] = fd[2]; ov[OP] = 1'b1; end \
                if (arb_g[OP][3]) begin od[OP] = fd[3]; ov[OP] = 1'b1; end \
                if (arb_g[OP][4]) begin od[OP] = fd[4]; ov[OP] = 1'b1; end \
            end \
        end

    `OUT_MUX(0, or0)
    `OUT_MUX(1, or1)
    `OUT_MUX(2, or2)
    `OUT_MUX(3, or3)
    `OUT_MUX(4, or4)

    // ---- FIFO pop: per input port, check if any output granted it ----
    `define FIFO_POP(IP) \
        always_comb begin \
            fr[IP] = (arb_g[0][IP] && arb_gv[0] && or0) || \
                     (arb_g[1][IP] && arb_gv[1] && or1) || \
                     (arb_g[2][IP] && arb_gv[2] && or2) || \
                     (arb_g[3][IP] && arb_gv[3] && or3) || \
                     (arb_g[4][IP] && arb_gv[4] && or4); \
        end

    `FIFO_POP(0)
    `FIFO_POP(1)
    `FIFO_POP(2)
    `FIFO_POP(3)
    `FIFO_POP(4)

    // ---- Drive output ports ----
    assign local_out_data = od[0]; assign local_out_valid = ov[0];
    assign north_out_data = od[1]; assign north_out_valid = ov[1];
    assign south_out_data = od[2]; assign south_out_valid = ov[2];
    assign east_out_data  = od[3]; assign east_out_valid  = ov[3];
    assign west_out_data  = od[4]; assign west_out_valid  = ov[4];

endmodule