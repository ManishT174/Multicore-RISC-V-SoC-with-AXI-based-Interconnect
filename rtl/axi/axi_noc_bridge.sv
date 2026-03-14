//============================================================================
// axi_noc_bridge.sv — AXI4-Lite ↔ NoC Flit Bridge (v2)
//
// Fixed: all ROB state in a single always_ff block.
//============================================================================

module axi_noc_bridge
    import noc_pkg::*;
    import axi_pkg::*;
#(
    parameter int MY_X = 0,
    parameter int MY_Y = 0,
    parameter int NUM_TXN = 4
)(
    input  logic clk,
    input  logic rst_n,

    // AXI4-Lite Slave interface (from axi_lite_master bridge)
    input  logic [31:0] s_axi_awaddr,
    input  logic [2:0]  s_axi_awprot,
    input  logic        s_axi_awvalid,
    output logic        s_axi_awready,

    input  logic [31:0] s_axi_wdata,
    input  logic [3:0]  s_axi_wstrb,
    input  logic        s_axi_wvalid,
    output logic        s_axi_wready,

    output logic [1:0]  s_axi_bresp,
    output logic        s_axi_bvalid,
    input  logic        s_axi_bready,

    input  logic [31:0] s_axi_araddr,
    input  logic [2:0]  s_axi_arprot,
    input  logic        s_axi_arvalid,
    output logic        s_axi_arready,

    output logic [31:0] s_axi_rdata,
    output logic [1:0]  s_axi_rresp,
    output logic        s_axi_rvalid,
    input  logic        s_axi_rready,

    // NoC Local port
    output logic [FLIT_W-1:0] noc_out_data,
    output logic               noc_out_valid,
    input  logic               noc_out_ready,

    input  logic [FLIT_W-1:0] noc_in_data,
    input  logic               noc_in_valid,
    output logic               noc_in_ready
);

    localparam int TXN_IDX_W = $clog2(NUM_TXN);

    // -----------------------------------------------------------------------
    // Packetization FSM
    // -----------------------------------------------------------------------
    typedef enum logic [2:0] {
        IDLE,
        TX_HEAD_WR,
        TX_DATA_WR,
        TX_HEAD_RD
    } tx_state_t;

    tx_state_t state;

    logic [31:0]          req_awaddr, req_wdata, req_araddr;
    logic [3:0]           req_wstrb;
    logic [TXN_ID_W-1:0] req_txn_id;
    logic [TXN_ID_W-1:0] next_txn_id;

    // -----------------------------------------------------------------------
    // Reorder Buffer — all state in one block
    // -----------------------------------------------------------------------
    logic [NUM_TXN-1:0]   rob_valid;
    logic [NUM_TXN-1:0]   rob_is_write;
    logic [31:0]           rob_data    [0:NUM_TXN-1];
    logic [1:0]            rob_resp    [0:NUM_TXN-1];
    logic [NUM_TXN-1:0]   txn_outstanding;  // Slot has been issued
    logic [TXN_IDX_W-1:0] rob_head;

    wire txn_full = &txn_outstanding;

    // Parse incoming response
    wire [2:0]           resp_type   = noc_in_data[127:125];
    wire [TXN_ID_W-1:0] resp_txn_id = noc_in_data[120:117];
    wire [1:0]           resp_resp   = noc_in_data[116:115];
    wire [31:0]          resp_data   = noc_in_data[82:51];

    wire resp_is_wr = (resp_type == FLIT_RESP_WR);
    wire resp_is_rd = (resp_type == FLIT_RESP_RD);
    wire resp_incoming = noc_in_valid && (resp_is_wr || resp_is_rd);

    // Retirement condition
    wire rob_head_valid = rob_valid[rob_head];
    wire rob_head_is_wr = rob_is_write[rob_head];
    wire retiring = rob_head_valid &&
                    ((rob_head_is_wr && s_axi_bvalid && s_axi_bready) ||
                     (!rob_head_is_wr && s_axi_rvalid && s_axi_rready));

    // Single always_ff for ALL ROB + txn state
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= IDLE;
            next_txn_id     <= '0;
            req_awaddr      <= '0;
            req_wdata       <= '0;
            req_wstrb       <= '0;
            req_araddr      <= '0;
            req_txn_id      <= '0;
            rob_valid       <= '0;
            rob_is_write    <= '0;
            txn_outstanding <= '0;
            rob_head        <= '0;
            for (int i = 0; i < NUM_TXN; i++) begin
                rob_data[i] <= '0;
                rob_resp[i] <= '0;
            end
        end else begin
            // --- Response reception: fill ROB slot ---
            if (resp_incoming) begin
                rob_valid[resp_txn_id[TXN_IDX_W-1:0]]    <= 1'b1;
                rob_is_write[resp_txn_id[TXN_IDX_W-1:0]] <= resp_is_wr;
                rob_data[resp_txn_id[TXN_IDX_W-1:0]]     <= resp_data;
                rob_resp[resp_txn_id[TXN_IDX_W-1:0]]     <= resp_resp;
            end

            // --- Retirement: drain ROB head ---
            if (retiring) begin
                rob_valid[rob_head]       <= 1'b0;
                txn_outstanding[rob_head] <= 1'b0;
                rob_head <= rob_head + 1;
            end

            // --- Packetization FSM ---
            case (state)
                IDLE: begin
                    if (s_axi_awvalid && s_axi_wvalid && !txn_full) begin
                        req_awaddr <= s_axi_awaddr;
                        req_wdata  <= s_axi_wdata;
                        req_wstrb  <= s_axi_wstrb;
                        req_txn_id <= next_txn_id;
                        state      <= TX_HEAD_WR;
                    end
                    else if (s_axi_arvalid && !s_axi_awvalid && !txn_full) begin
                        req_araddr <= s_axi_araddr;
                        req_txn_id <= next_txn_id;
                        state      <= TX_HEAD_RD;
                    end
                end

                TX_HEAD_WR: begin
                    if (noc_out_valid && noc_out_ready) begin
                        state <= TX_DATA_WR;
                    end
                end

                TX_DATA_WR: begin
                    if (noc_out_valid && noc_out_ready) begin
                        // Mark slot as outstanding
                        txn_outstanding[req_txn_id[TXN_IDX_W-1:0]] <= 1'b1;
                        next_txn_id <= next_txn_id + 1;
                        state <= IDLE;
                    end
                end

                TX_HEAD_RD: begin
                    if (noc_out_valid && noc_out_ready) begin
                        txn_outstanding[req_txn_id[TXN_IDX_W-1:0]] <= 1'b1;
                        next_txn_id <= next_txn_id + 1;
                        state <= IDLE;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

    // AXI handshakes
    assign s_axi_awready = (state == IDLE) && !txn_full;
    assign s_axi_wready  = (state == IDLE) && !txn_full;
    assign s_axi_arready = (state == IDLE) && !s_axi_awvalid && !txn_full;

    // Always accept NoC responses
    assign noc_in_ready = 1'b1;

    // -----------------------------------------------------------------------
    // Flit construction
    // -----------------------------------------------------------------------
    logic [TILE_ID_W-1:0] wr_dst_tile, rd_dst_tile;
    assign wr_dst_tile = addr_to_tile(req_awaddr);
    assign rd_dst_tile = addr_to_tile(req_araddr);

    noc_flit_t head_wr_flit, data_wr_flit, head_rd_flit;

    always_comb begin
        head_wr_flit = '0;
        head_wr_flit.flit_type = FLIT_HEAD_WR;
        head_wr_flit.src_x  = MY_X[COORD_W-1:0];
        head_wr_flit.src_y  = MY_Y[COORD_W-1:0];
        head_wr_flit.dst_x  = tile_to_x(wr_dst_tile);
        head_wr_flit.dst_y  = tile_to_y(wr_dst_tile);
        head_wr_flit.txn_id = req_txn_id;
        head_wr_flit.addr   = req_awaddr;

        data_wr_flit = '0;
        data_wr_flit.flit_type = FLIT_DATA;
        data_wr_flit.src_x  = MY_X[COORD_W-1:0];
        data_wr_flit.src_y  = MY_Y[COORD_W-1:0];
        data_wr_flit.dst_x  = tile_to_x(wr_dst_tile);
        data_wr_flit.dst_y  = tile_to_y(wr_dst_tile);
        data_wr_flit.txn_id = req_txn_id;
        data_wr_flit.data   = req_wdata;
        data_wr_flit.be     = req_wstrb;

        head_rd_flit = '0;
        head_rd_flit.flit_type = FLIT_HEAD_RD;
        head_rd_flit.src_x  = MY_X[COORD_W-1:0];
        head_rd_flit.src_y  = MY_Y[COORD_W-1:0];
        head_rd_flit.dst_x  = tile_to_x(rd_dst_tile);
        head_rd_flit.dst_y  = tile_to_y(rd_dst_tile);
        head_rd_flit.txn_id = req_txn_id;
        head_rd_flit.addr   = req_araddr;
    end

    // NoC output mux
    always_comb begin
        noc_out_valid = 1'b0;
        noc_out_data  = '0;
        case (state)
            TX_HEAD_WR: begin noc_out_data = head_wr_flit; noc_out_valid = 1'b1; end
            TX_DATA_WR: begin noc_out_data = data_wr_flit; noc_out_valid = 1'b1; end
            TX_HEAD_RD: begin noc_out_data = head_rd_flit; noc_out_valid = 1'b1; end
            default: ;
        endcase
    end

    // -----------------------------------------------------------------------
    // AXI response outputs
    // -----------------------------------------------------------------------
    assign s_axi_bvalid = rob_head_valid && rob_head_is_wr;
    assign s_axi_bresp  = rob_resp[rob_head];

    assign s_axi_rvalid = rob_head_valid && !rob_head_is_wr;
    assign s_axi_rdata  = rob_data[rob_head];
    assign s_axi_rresp  = rob_resp[rob_head];

endmodule