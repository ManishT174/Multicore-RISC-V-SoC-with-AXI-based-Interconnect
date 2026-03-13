//============================================================================
// axi_pkg.sv — AXI4-Lite Package
//
// Defines AXI-Lite channel structs and parameters.
// Uses packed structs for portability across Icarus/Verilator/Vivado.
//
// AXI4-Lite channels (no bursts, no caches, no QoS):
//   AW — Write Address   (addr, prot, valid/ready)
//   W  — Write Data      (data, strb, valid/ready)
//   B  — Write Response  (resp, valid/ready)
//   AR — Read Address    (addr, prot, valid/ready)
//   R  — Read Data       (data, resp, valid/ready)
//============================================================================

package axi_pkg;

    // -----------------------------------------------------------------------
    // Parameters
    // -----------------------------------------------------------------------
    parameter int AXI_ADDR_WIDTH = 32;
    parameter int AXI_DATA_WIDTH = 32;
    parameter int AXI_STRB_WIDTH = AXI_DATA_WIDTH / 8;

    // -----------------------------------------------------------------------
    // Response codes
    // -----------------------------------------------------------------------
    parameter logic [1:0] AXI_RESP_OKAY   = 2'b00;
    parameter logic [1:0] AXI_RESP_EXOKAY = 2'b01;
    parameter logic [1:0] AXI_RESP_SLVERR = 2'b10;
    parameter logic [1:0] AXI_RESP_DECERR = 2'b11;

    // -----------------------------------------------------------------------
    // AW channel — Write Address (master → slave)
    // -----------------------------------------------------------------------
    typedef struct packed {
        logic [AXI_ADDR_WIDTH-1:0] awaddr;
        logic [2:0]                awprot;
    } aw_chan_t;

    // -----------------------------------------------------------------------
    // W channel — Write Data (master → slave)
    // -----------------------------------------------------------------------
    typedef struct packed {
        logic [AXI_DATA_WIDTH-1:0] wdata;
        logic [AXI_STRB_WIDTH-1:0] wstrb;
    } w_chan_t;

    // -----------------------------------------------------------------------
    // B channel — Write Response (slave → master)
    // -----------------------------------------------------------------------
    typedef struct packed {
        logic [1:0] bresp;
    } b_chan_t;

    // -----------------------------------------------------------------------
    // AR channel — Read Address (master → slave)
    // -----------------------------------------------------------------------
    typedef struct packed {
        logic [AXI_ADDR_WIDTH-1:0] araddr;
        logic [2:0]                arprot;
    } ar_chan_t;

    // -----------------------------------------------------------------------
    // R channel — Read Data (slave → master)
    // -----------------------------------------------------------------------
    typedef struct packed {
        logic [AXI_DATA_WIDTH-1:0] rdata;
        logic [1:0]                rresp;
    } r_chan_t;

endpackage