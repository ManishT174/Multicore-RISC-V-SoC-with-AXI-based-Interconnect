//============================================================================
// soc_pkg.sv — SoC Parameters & Type Definitions
//
// Single source of truth for:
//   - Address map regions and decode
//   - Bus widths
//   - Peripheral register offsets
//   - Common types
//============================================================================

package soc_pkg;

    // -----------------------------------------------------------------------
    // Bus parameters
    // -----------------------------------------------------------------------
    parameter int ADDR_WIDTH = 32;
    parameter int DATA_WIDTH = 32;
    parameter int STRB_WIDTH = DATA_WIDTH / 8;

    // -----------------------------------------------------------------------
    // Memory Map
    //
    //  0x0000_0000 — 0x0000_3FFF : Boot ROM       (16 KB)
    //  0x8000_0000 — 0x8000_FFFF : Main RAM       (64 KB)
    //  0xF000_0000 — 0xF000_0FFF : UART           (4 KB)
    //  0xF001_0000 — 0xF001_0FFF : Timer          (4 KB)
    //  0xF002_0000 — 0xF002_0FFF : System Control (4 KB)
    // -----------------------------------------------------------------------
    parameter logic [31:0] ROM_BASE      = 32'h0000_0000;
    parameter logic [31:0] ROM_SIZE      = 32'h0000_4000;  // 16 KB
    parameter logic [31:0] ROM_MASK      = 32'h0000_3FFF;

    parameter logic [31:0] RAM_BASE      = 32'h8000_0000;
    parameter logic [31:0] RAM_SIZE      = 32'h0001_0000;  // 64 KB
    parameter logic [31:0] RAM_MASK      = 32'h0000_FFFF;

    parameter logic [31:0] UART_BASE     = 32'hF000_0000;
    parameter logic [31:0] UART_SIZE     = 32'h0000_1000;  // 4 KB
    parameter logic [31:0] UART_MASK     = 32'h0000_0FFF;

    parameter logic [31:0] TIMER_BASE    = 32'hF001_0000;
    parameter logic [31:0] TIMER_SIZE    = 32'h0000_1000;
    parameter logic [31:0] TIMER_MASK    = 32'h0000_0FFF;

    parameter logic [31:0] SYSCTRL_BASE  = 32'hF002_0000;
    parameter logic [31:0] SYSCTRL_SIZE  = 32'h0000_1000;
    parameter logic [31:0] SYSCTRL_MASK  = 32'h0000_0FFF;

    // Slave port indices (for address decoder → crossbar routing)
    typedef enum logic [2:0] {
        SLAVE_ROM     = 3'd0,
        SLAVE_RAM     = 3'd1,
        SLAVE_UART    = 3'd2,
        SLAVE_TIMER   = 3'd3,
        SLAVE_SYSCTRL = 3'd4,
        SLAVE_NONE    = 3'd7   // Decode error
    } slave_id_t;

    parameter int NUM_SLAVES = 5;

    // -----------------------------------------------------------------------
    // UART Register Offsets
    // -----------------------------------------------------------------------
    parameter logic [7:0] UART_TX_DATA   = 8'h00;  // [7:0] TX data, write triggers send
    parameter logic [7:0] UART_TX_STATUS = 8'h04;  // [0] TX busy, [1] TX FIFO full
    parameter logic [7:0] UART_RX_DATA   = 8'h08;  // [7:0] RX data
    parameter logic [7:0] UART_RX_STATUS = 8'h0C;  // [0] RX data valid
    parameter logic [7:0] UART_CTRL      = 8'h10;  // [15:0] Baud divisor
    parameter logic [7:0] UART_IRQ_EN    = 8'h14;  // [0] TX done IRQ, [1] RX valid IRQ

    // -----------------------------------------------------------------------
    // Timer Register Offsets
    // -----------------------------------------------------------------------
    parameter logic [7:0] TIMER_MTIME_LO    = 8'h00;  // mtime[31:0]
    parameter logic [7:0] TIMER_MTIME_HI    = 8'h04;  // mtime[63:32]
    parameter logic [7:0] TIMER_MTIMECMP_LO = 8'h08;  // mtimecmp[31:0]
    parameter logic [7:0] TIMER_MTIMECMP_HI = 8'h0C;  // mtimecmp[63:32]
    parameter logic [7:0] TIMER_CTRL        = 8'h10;  // [0] enable

    // -----------------------------------------------------------------------
    // System Control Register Offsets
    // -----------------------------------------------------------------------
    parameter logic [7:0] SYSCTRL_HART_ID   = 8'h00;  // Read-only: hart ID
    parameter logic [7:0] SYSCTRL_NUM_HARTS = 8'h04;  // Read-only: number of harts
    parameter logic [7:0] SYSCTRL_BOOT_ADDR = 8'h08;  // R/W: boot address
    parameter logic [7:0] SYSCTRL_SCRATCH   = 8'h0C;  // R/W: general purpose scratch

    // -----------------------------------------------------------------------
    // Simple memory bus interface type (before AXI bridge)
    // -----------------------------------------------------------------------
    typedef struct packed {
        logic [31:0] addr;
        logic [31:0] wdata;
        logic        rd;
        logic        wr;
        logic [3:0]  be;
    } mem_req_t;

    typedef struct packed {
        logic [31:0] rdata;
        logic        valid;
        logic        error;
    } mem_resp_t;

endpackage