//============================================================================
// axi_lite_slave.sv — AXI4-Lite Slave-to-Peripheral Bridge
//
// Converts AXI-Lite slave transactions into the simple peripheral bus
// interface (addr, rd, wr, wdata, be, rdata). Peripherals respond
// combinationally (0-cycle), so this bridge can complete transactions
// quickly.
//
// Handles:
//   - Independent AW/W acceptance (either can arrive first)
//   - Single-cycle peripheral access once both addr+data available
//   - Read: AR → peripheral read → R response
//   - Write: AW+W → peripheral write → B response
//============================================================================

module axi_lite_slave
    import axi_pkg::*;
(
    input  logic        clk,
    input  logic        rst_n,

    // ---- AXI-Lite Slave interface ----
    // Write Address
    input  logic [31:0] s_axi_awaddr,
    input  logic [2:0]  s_axi_awprot,
    input  logic        s_axi_awvalid,
    output logic        s_axi_awready,

    // Write Data
    input  logic [31:0] s_axi_wdata,
    input  logic [3:0]  s_axi_wstrb,
    input  logic        s_axi_wvalid,
    output logic        s_axi_wready,

    // Write Response
    output logic [1:0]  s_axi_bresp,
    output logic        s_axi_bvalid,
    input  logic        s_axi_bready,

    // Read Address
    input  logic [31:0] s_axi_araddr,
    input  logic [2:0]  s_axi_arprot,
    input  logic        s_axi_arvalid,
    output logic        s_axi_arready,

    // Read Data
    output logic [31:0] s_axi_rdata,
    output logic [1:0]  s_axi_rresp,
    output logic        s_axi_rvalid,
    input  logic        s_axi_rready,

    // ---- Peripheral interface ----
    output logic [31:0] periph_addr,
    output logic [31:0] periph_wdata,
    output logic        periph_rd,
    output logic        periph_wr,
    output logic [3:0]  periph_be,
    input  logic [31:0] periph_rdata,
    input  logic        periph_valid     // Directly from peripheral (combinational)
);

    // -----------------------------------------------------------------------
    // State machine
    // -----------------------------------------------------------------------
    typedef enum logic [2:0] {
        IDLE,
        WR_WAIT_W,     // AW received, waiting for W
        WR_WAIT_AW,    // W received, waiting for AW
        WR_RESP,       // Write done, sending B
        RD_RESP        // Read done, sending R
    } state_t;

    state_t state;

    // Latched channels
    logic [31:0] aw_addr_r;
    logic [31:0] w_data_r;
    logic [3:0]  w_strb_r;

    // -----------------------------------------------------------------------
    // Main FSM
    // -----------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= IDLE;
            aw_addr_r  <= '0;
            w_data_r   <= '0;
            w_strb_r   <= '0;
        end else begin
            case (state)
                IDLE: begin
                    // Write: check if AW and/or W arrive
                    if (s_axi_awvalid && s_axi_wvalid) begin
                        // Both arrive simultaneously — do write, go to B
                        aw_addr_r <= s_axi_awaddr;
                        w_data_r  <= s_axi_wdata;
                        w_strb_r  <= s_axi_wstrb;
                        state     <= WR_RESP;
                    end else if (s_axi_awvalid) begin
                        aw_addr_r <= s_axi_awaddr;
                        state     <= WR_WAIT_W;
                    end else if (s_axi_wvalid) begin
                        w_data_r  <= s_axi_wdata;
                        w_strb_r  <= s_axi_wstrb;
                        state     <= WR_WAIT_AW;
                    end else if (s_axi_arvalid) begin
                        // Read request
                        state <= RD_RESP;
                    end
                end

                WR_WAIT_W: begin
                    if (s_axi_wvalid) begin
                        w_data_r <= s_axi_wdata;
                        w_strb_r <= s_axi_wstrb;
                        state    <= WR_RESP;
                    end
                end

                WR_WAIT_AW: begin
                    if (s_axi_awvalid) begin
                        aw_addr_r <= s_axi_awaddr;
                        state     <= WR_RESP;
                    end
                end

                WR_RESP: begin
                    // B response handshake
                    if (s_axi_bvalid && s_axi_bready)
                        state <= IDLE;
                end

                RD_RESP: begin
                    // R response handshake
                    if (s_axi_rvalid && s_axi_rready)
                        state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

    // -----------------------------------------------------------------------
    // AXI handshake outputs
    // -----------------------------------------------------------------------

    // Accept AW in IDLE or WR_WAIT_AW
    assign s_axi_awready = (state == IDLE) || (state == WR_WAIT_AW);

    // Accept W in IDLE or WR_WAIT_W
    assign s_axi_wready = (state == IDLE) || (state == WR_WAIT_W);

    // Accept AR only in IDLE (writes have priority by convention)
    assign s_axi_arready = (state == IDLE) && !s_axi_awvalid && !s_axi_wvalid;

    // B response: valid in WR_RESP state
    assign s_axi_bvalid = (state == WR_RESP);
    assign s_axi_bresp  = AXI_RESP_OKAY;

    // R response: valid in RD_RESP state
    assign s_axi_rvalid = (state == RD_RESP);
    assign s_axi_rresp  = AXI_RESP_OKAY;
    assign s_axi_rdata  = periph_rdata;

    // -----------------------------------------------------------------------
    // Peripheral interface
    // -----------------------------------------------------------------------

    // For writes: drive peripheral during WR_RESP
    // For reads: drive peripheral during RD_RESP using latched AR address
    logic [31:0] ar_addr_r;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            ar_addr_r <= '0;
        else if (state == IDLE && s_axi_arvalid && s_axi_arready)
            ar_addr_r <= s_axi_araddr;
    end

    assign periph_addr  = (state == WR_RESP) ? aw_addr_r : ar_addr_r;
    assign periph_wdata = w_data_r;
    assign periph_be    = (state == WR_RESP) ? w_strb_r : 4'b1111;
    assign periph_wr    = (state == WR_RESP);
    assign periph_rd    = (state == RD_RESP);

endmodule