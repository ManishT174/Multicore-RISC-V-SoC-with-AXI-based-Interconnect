//============================================================================
// axi_lite_master.sv — Core-to-AXI4-Lite Master Bridge
//
// Converts the processor core's simple memory interface into AXI4-Lite
// transactions. Handles one outstanding transaction at a time.
//
// Core interface:      AXI-Lite interface:
//   addr, wdata          AW, W, AR channels (master → slave)
//   rd, wr, be           B, R channels      (slave → master)
//   rdata, valid
//
// Protocol:
//   Write: Assert AW+W simultaneously, wait for B response
//   Read:  Assert AR, wait for R response
//   Core is stalled (valid deasserted) until AXI transaction completes
//============================================================================

module axi_lite_master
    import axi_pkg::*;
(
    input  logic        clk,
    input  logic        rst_n,

    // ---- Core-side interface ----
    input  logic [31:0] core_addr,
    input  logic [31:0] core_wdata,
    input  logic        core_rd,
    input  logic        core_wr,
    input  logic [3:0]  core_be,
    output logic [31:0] core_rdata,
    output logic        core_valid,     // Transaction complete, data ready

    // ---- AXI-Lite Master interface ----
    // Write Address channel
    output logic [31:0] m_axi_awaddr,
    output logic [2:0]  m_axi_awprot,
    output logic        m_axi_awvalid,
    input  logic        m_axi_awready,

    // Write Data channel
    output logic [31:0] m_axi_wdata,
    output logic [3:0]  m_axi_wstrb,
    output logic        m_axi_wvalid,
    input  logic        m_axi_wready,

    // Write Response channel
    input  logic [1:0]  m_axi_bresp,
    input  logic        m_axi_bvalid,
    output logic        m_axi_bready,

    // Read Address channel
    output logic [31:0] m_axi_araddr,
    output logic [2:0]  m_axi_arprot,
    output logic        m_axi_arvalid,
    input  logic        m_axi_arready,

    // Read Data channel
    input  logic [31:0] m_axi_rdata,
    input  logic [1:0]  m_axi_rresp,
    input  logic        m_axi_rvalid,
    output logic        m_axi_rready
);

    // -----------------------------------------------------------------------
    // State machine
    // -----------------------------------------------------------------------
    typedef enum logic [2:0] {
        IDLE,
        WR_ADDR,        // AW accepted, waiting for W
        WR_DATA,        // W accepted, waiting for AW
        WR_RESP,        // AW+W both accepted, waiting for B
        RD_ADDR,        // AR pending
        RD_RESP         // AR accepted, waiting for R
    } state_t;

    state_t state, state_next;

    // Latched request
    logic [31:0] req_addr;
    logic [31:0] req_wdata;
    logic [3:0]  req_be;
    logic        req_is_write;

    // Track which write channels have been accepted
    logic aw_done, w_done;

    // -----------------------------------------------------------------------
    // State register
    // -----------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= IDLE;
        else
            state <= state_next;
    end

    // -----------------------------------------------------------------------
    // Latch request on acceptance
    // -----------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            req_addr     <= '0;
            req_wdata    <= '0;
            req_be       <= '0;
            req_is_write <= 1'b0;
        end else if (state == IDLE && (core_rd || core_wr)) begin
            req_addr     <= core_addr;
            req_wdata    <= core_wdata;
            req_be       <= core_be;
            req_is_write <= core_wr;
        end
    end

    // Track AW/W channel acceptance independently
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            aw_done <= 1'b0;
            w_done  <= 1'b0;
        end else if (state == IDLE) begin
            aw_done <= 1'b0;
            w_done  <= 1'b0;
        end else begin
            if (m_axi_awvalid && m_axi_awready) aw_done <= 1'b1;
            if (m_axi_wvalid  && m_axi_wready)  w_done  <= 1'b1;
        end
    end

    // -----------------------------------------------------------------------
    // Next-state logic
    // -----------------------------------------------------------------------
    always_comb begin
        state_next = state;

        case (state)
            IDLE: begin
                if (core_wr)
                    state_next = WR_RESP;  // Present AW+W together
                else if (core_rd)
                    state_next = RD_ADDR;
            end

            WR_RESP: begin
                // Stay until both AW and W accepted AND B received
                if ((aw_done || (m_axi_awvalid && m_axi_awready)) &&
                    (w_done  || (m_axi_wvalid  && m_axi_wready)) &&
                    m_axi_bvalid)
                    state_next = IDLE;
                // If only AW accepted
                else if ((aw_done || (m_axi_awvalid && m_axi_awready)) &&
                         !(w_done || (m_axi_wvalid && m_axi_wready)))
                    state_next = WR_DATA;
                // If only W accepted
                else if (!(aw_done || (m_axi_awvalid && m_axi_awready)) &&
                         (w_done || (m_axi_wvalid && m_axi_wready)))
                    state_next = WR_ADDR;
            end

            WR_ADDR: begin
                if (m_axi_awvalid && m_axi_awready) begin
                    if (m_axi_bvalid)
                        state_next = IDLE;
                    else
                        state_next = WR_RESP; // Reuse WR_RESP to wait for B
                end
            end

            WR_DATA: begin
                if (m_axi_wvalid && m_axi_wready) begin
                    if (m_axi_bvalid)
                        state_next = IDLE;
                    else
                        state_next = WR_RESP;
                end
            end

            RD_ADDR: begin
                if (m_axi_arvalid && m_axi_arready)
                    state_next = RD_RESP;
            end

            RD_RESP: begin
                if (m_axi_rvalid)
                    state_next = IDLE;
            end

            default: state_next = IDLE;
        endcase
    end

    // -----------------------------------------------------------------------
    // Output logic
    // -----------------------------------------------------------------------

    // Write Address channel
    assign m_axi_awaddr  = req_addr;
    assign m_axi_awprot  = 3'b000;
    assign m_axi_awvalid = (state == WR_RESP && !aw_done) ||
                           (state == WR_ADDR);

    // Write Data channel
    assign m_axi_wdata  = req_wdata;
    assign m_axi_wstrb  = req_be;
    assign m_axi_wvalid = (state == WR_RESP && !w_done) ||
                          (state == WR_DATA);

    // Write Response — always ready when waiting
    assign m_axi_bready = (state == WR_RESP) || (state == WR_ADDR) || (state == WR_DATA);

    // Read Address channel
    assign m_axi_araddr  = req_addr;
    assign m_axi_arprot  = 3'b000;
    assign m_axi_arvalid = (state == RD_ADDR);

    // Read Data — always ready when waiting for response
    assign m_axi_rready = (state == RD_RESP);

    // -----------------------------------------------------------------------
    // Core-side response
    // -----------------------------------------------------------------------
    // Transaction completes when:
    //   Write: B response received
    //   Read:  R response received
    assign core_valid = ((state == WR_RESP || state == WR_ADDR || state == WR_DATA) &&
                          m_axi_bvalid && m_axi_bready) ||
                        (state == RD_RESP && m_axi_rvalid && m_axi_rready) ||
                        (state == IDLE && !(core_rd || core_wr));

    assign core_rdata = m_axi_rdata;

endmodule