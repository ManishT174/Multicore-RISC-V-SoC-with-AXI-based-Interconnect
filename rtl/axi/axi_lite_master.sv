//============================================================================
// axi_lite_master.sv — Core-to-AXI4-Lite Master Bridge (v2)
//
// Simplified state machine with explicit WAIT_B / WAIT_R states.
// Handles one outstanding transaction at a time.
//
//   Write: IDLE → WR_AW_W (present AW+W) → WAIT_B (wait for bresp) → IDLE
//   Read:  IDLE → RD_AR (present AR) → WAIT_R (wait for rdata) → IDLE
//
// AW and W are always presented simultaneously. If a slave accepts
// one before the other, we track which is done and keep presenting
// the remaining one.
//============================================================================

module axi_lite_master
    import axi_pkg::*;
(
    input  logic        clk,
    input  logic        rst_n,

    // Core-side interface
    input  logic [31:0] core_addr,
    input  logic [31:0] core_wdata,
    input  logic        core_rd,
    input  logic        core_wr,
    input  logic [3:0]  core_be,
    output logic [31:0] core_rdata,
    output logic        core_valid,

    // AXI-Lite Master interface
    output logic [31:0] m_axi_awaddr,
    output logic [2:0]  m_axi_awprot,
    output logic        m_axi_awvalid,
    input  logic        m_axi_awready,

    output logic [31:0] m_axi_wdata,
    output logic [3:0]  m_axi_wstrb,
    output logic        m_axi_wvalid,
    input  logic        m_axi_wready,

    input  logic [1:0]  m_axi_bresp,
    input  logic        m_axi_bvalid,
    output logic        m_axi_bready,

    output logic [31:0] m_axi_araddr,
    output logic [2:0]  m_axi_arprot,
    output logic        m_axi_arvalid,
    input  logic        m_axi_arready,

    input  logic [31:0] m_axi_rdata,
    input  logic [1:0]  m_axi_rresp,
    input  logic        m_axi_rvalid,
    output logic        m_axi_rready
);

    typedef enum logic [2:0] {
        IDLE,
        WR_AW_W,    // Presenting AW and W channels
        WAIT_B,     // AW+W accepted, waiting for B response
        RD_AR,      // Presenting AR channel
        WAIT_R      // AR accepted, waiting for R response
    } state_t;

    state_t state;

    // Latched request
    logic [31:0] req_addr, req_wdata;
    logic [3:0]  req_be;

    // Track AW/W acceptance independently within WR_AW_W state
    logic aw_accepted, w_accepted;

    // Both channels accepted?
    wire aw_done_now = aw_accepted || (m_axi_awvalid && m_axi_awready);
    wire w_done_now  = w_accepted  || (m_axi_wvalid  && m_axi_wready);
    wire both_accepted = aw_done_now && w_done_now;

    // -----------------------------------------------------------------------
    // State machine
    // -----------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= IDLE;
            req_addr    <= '0;
            req_wdata   <= '0;
            req_be      <= '0;
            aw_accepted <= 1'b0;
            w_accepted  <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    aw_accepted <= 1'b0;
                    w_accepted  <= 1'b0;
                    if (core_wr) begin
                        req_addr  <= core_addr;
                        req_wdata <= core_wdata;
                        req_be    <= core_be;
                        state     <= WR_AW_W;
                    end else if (core_rd) begin
                        req_addr <= core_addr;
                        state    <= RD_AR;
                    end
                end

                WR_AW_W: begin
                    // Track individual channel acceptance
                    if (m_axi_awvalid && m_axi_awready) aw_accepted <= 1'b1;
                    if (m_axi_wvalid  && m_axi_wready)  w_accepted  <= 1'b1;

                    // Both accepted? Check if B already available
                    if (both_accepted) begin
                        if (m_axi_bvalid)
                            state <= IDLE;  // Lucky: B came same cycle
                        else
                            state <= WAIT_B;
                    end
                end

                WAIT_B: begin
                    if (m_axi_bvalid && m_axi_bready)
                        state <= IDLE;
                end

                RD_AR: begin
                    if (m_axi_arvalid && m_axi_arready) begin
                        if (m_axi_rvalid)
                            state <= IDLE;  // Lucky: R came same cycle
                        else
                            state <= WAIT_R;
                    end
                end

                WAIT_R: begin
                    if (m_axi_rvalid && m_axi_rready)
                        state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

    // -----------------------------------------------------------------------
    // AXI output signals
    // -----------------------------------------------------------------------

    // Write Address
    assign m_axi_awaddr  = req_addr;
    assign m_axi_awprot  = 3'b000;
    assign m_axi_awvalid = (state == WR_AW_W) && !aw_accepted;

    // Write Data
    assign m_axi_wdata  = req_wdata;
    assign m_axi_wstrb  = req_be;
    assign m_axi_wvalid = (state == WR_AW_W) && !w_accepted;

    // Write Response — ready in WR_AW_W (in case of same-cycle B) and WAIT_B
    assign m_axi_bready = (state == WR_AW_W) || (state == WAIT_B);

    // Read Address
    assign m_axi_araddr  = req_addr;
    assign m_axi_arprot  = 3'b000;
    assign m_axi_arvalid = (state == RD_AR);

    // Read Data — ready in RD_AR (same-cycle) and WAIT_R
    assign m_axi_rready = (state == RD_AR) || (state == WAIT_R);

    // -----------------------------------------------------------------------
    // Core-side response
    // -----------------------------------------------------------------------
    wire wr_completing = (state == WAIT_B && m_axi_bvalid) ||
                         (state == WR_AW_W && both_accepted && m_axi_bvalid);
    wire rd_completing = (state == WAIT_R && m_axi_rvalid) ||
                         (state == RD_AR && m_axi_arready && m_axi_rvalid);

    assign core_valid = (state == IDLE) || wr_completing || rd_completing;
    assign core_rdata = m_axi_rdata;

endmodule