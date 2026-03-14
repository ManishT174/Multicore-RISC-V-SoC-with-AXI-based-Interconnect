//============================================================================
// noc_slave_bridge.sv — NoC Flit → Peripheral Bus Bridge
//
// Sits at a target tile and translates incoming NoC request flits
// into peripheral bus transactions, then sends response flits back.
//
// Write flow:  receive HEAD_WR → receive DATA → perform write → send RESP_WR
// Read flow:   receive HEAD_RD → perform read → send RESP_RD (with data)
//
// Connects to peripherals via the same simple bus interface
// (addr, wdata, rd, wr, be, rdata).
//============================================================================

module noc_slave_bridge
    import noc_pkg::*;
    import axi_pkg::*;
(
    input  logic clk,
    input  logic rst_n,

    // ---- NoC Local port (from mesh router) ----
    input  logic [FLIT_W-1:0] noc_in_data,
    input  logic               noc_in_valid,
    output logic               noc_in_ready,

    output logic [FLIT_W-1:0] noc_out_data,
    output logic               noc_out_valid,
    input  logic               noc_out_ready,

    // ---- Peripheral bus ----
    output logic [31:0] periph_addr,
    output logic [31:0] periph_wdata,
    output logic        periph_rd,
    output logic        periph_wr,
    output logic [3:0]  periph_be,
    input  logic [31:0] periph_rdata,
    input  logic        periph_valid
);

    typedef enum logic [2:0] {
        IDLE,
        WAIT_WDATA,     // Got write header, waiting for data flit
        DO_WRITE,       // Perform write, send RESP_WR
        SEND_WR_RESP,   // Sending write response flit
        DO_READ,        // Perform read
        SEND_RD_RESP    // Sending read response flit
    } state_t;

    state_t state;

    // Latched request fields
    logic [COORD_W-1:0]  req_src_x, req_src_y;
    logic [TXN_ID_W-1:0] req_txn_id;
    logic [31:0]          req_addr;
    logic [31:0]          req_wdata;
    logic [3:0]           req_be;
    logic [31:0]          resp_rdata;

    // Parse incoming flit
    noc_flit_t in_flit;
    assign in_flit = noc_in_data;

    // -----------------------------------------------------------------------
    // FSM
    // -----------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= IDLE;
            req_src_x  <= '0;
            req_src_y  <= '0;
            req_txn_id <= '0;
            req_addr   <= '0;
            req_wdata  <= '0;
            req_be     <= '0;
            resp_rdata <= '0;
        end else begin
            case (state)
                IDLE: begin
                    if (noc_in_valid && noc_in_ready) begin
                        req_src_x  <= in_flit.src_x;
                        req_src_y  <= in_flit.src_y;
                        req_txn_id <= in_flit.txn_id;
                        req_addr   <= in_flit.addr;

                        if (in_flit.flit_type == FLIT_HEAD_WR)
                            state <= WAIT_WDATA;
                        else if (in_flit.flit_type == FLIT_HEAD_RD)
                            state <= DO_READ;
                        // Other flit types: ignore
                    end
                end

                WAIT_WDATA: begin
                    if (noc_in_valid && noc_in_ready) begin
                        if (in_flit.flit_type == FLIT_DATA) begin
                            req_wdata <= in_flit.data;
                            req_be    <= in_flit.be;
                            state     <= DO_WRITE;
                        end
                    end
                end

                DO_WRITE: begin
                    // Write happens this cycle (combinational peripheral)
                    state <= SEND_WR_RESP;
                end

                SEND_WR_RESP: begin
                    if (noc_out_valid && noc_out_ready)
                        state <= IDLE;
                end

                DO_READ: begin
                    // Read happens this cycle, capture result
                    resp_rdata <= periph_rdata;
                    state <= SEND_RD_RESP;
                end

                SEND_RD_RESP: begin
                    if (noc_out_valid && noc_out_ready)
                        state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

    // -----------------------------------------------------------------------
    // NoC input handshake
    // -----------------------------------------------------------------------
    assign noc_in_ready = (state == IDLE) || (state == WAIT_WDATA);

    // -----------------------------------------------------------------------
    // Peripheral bus drive
    // -----------------------------------------------------------------------
    assign periph_addr  = req_addr;
    assign periph_wdata = req_wdata;
    assign periph_be    = req_be;
    assign periph_wr    = (state == DO_WRITE);
    assign periph_rd    = (state == DO_READ);

    // -----------------------------------------------------------------------
    // Response flit construction
    // -----------------------------------------------------------------------
    noc_flit_t wr_resp_flit, rd_resp_flit;

    always_comb begin
        wr_resp_flit = '0;
        wr_resp_flit.flit_type = FLIT_RESP_WR;
        wr_resp_flit.src_x     = in_flit.dst_x;  // We are the destination
        wr_resp_flit.src_y     = in_flit.dst_y;
        wr_resp_flit.dst_x     = req_src_x;       // Route back to requester
        wr_resp_flit.dst_y     = req_src_y;
        wr_resp_flit.txn_id    = req_txn_id;
        wr_resp_flit.resp      = AXI_RESP_OKAY;

        rd_resp_flit = '0;
        rd_resp_flit.flit_type = FLIT_RESP_RD;
        rd_resp_flit.src_x     = in_flit.dst_x;
        rd_resp_flit.src_y     = in_flit.dst_y;
        rd_resp_flit.dst_x     = req_src_x;
        rd_resp_flit.dst_y     = req_src_y;
        rd_resp_flit.txn_id    = req_txn_id;
        rd_resp_flit.resp      = AXI_RESP_OKAY;
        rd_resp_flit.data      = resp_rdata;
    end

    // NoC output mux
    always_comb begin
        noc_out_valid = 1'b0;
        noc_out_data  = '0;
        case (state)
            SEND_WR_RESP: begin noc_out_data = wr_resp_flit; noc_out_valid = 1'b1; end
            SEND_RD_RESP: begin noc_out_data = rd_resp_flit; noc_out_valid = 1'b1; end
            default: ;
        endcase
    end

endmodule