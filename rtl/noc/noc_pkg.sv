//============================================================================
// noc_pkg.sv — Network-on-Chip Packet Definitions
//
// Defines the flit (flow control unit) format that travels through the
// mesh network. Flits carry routing information + payload.
//
// Flit types:
//   HEAD   — Contains routing header (src, dst, type, ID, address)
//   DATA   — Contains write data + byte enables
//   RESP   — Contains read response data or write acknowledgment
//
// For single-beat AXI4-Lite transactions:
//   Write request: HEAD flit (addr) + DATA flit (wdata)
//   Read request:  HEAD flit (addr)
//   Write response: RESP flit (bresp)
//   Read response:  RESP flit (rdata + rresp)
//
// Mesh coordinates: (x, y) where x=column, y=row
//   For 2×2:  (0,0)=tile0  (1,0)=tile1  (0,1)=tile2  (1,1)=tile3
//============================================================================

package noc_pkg;

    // -----------------------------------------------------------------------
    // Mesh parameters
    // -----------------------------------------------------------------------
    parameter int MESH_X     = 2;
    parameter int MESH_Y     = 2;
    parameter int NUM_TILES  = MESH_X * MESH_Y;   // 4
    parameter int COORD_W    = 1;   // Bits for X or Y coordinate (log2(2)=1)
    parameter int TILE_ID_W  = 2;   // Bits for flat tile ID (log2(4)=2)
    parameter int TXN_ID_W   = 4;   // Transaction ID width (up to 16 outstanding)

    // -----------------------------------------------------------------------
    // Flit type encoding
    // -----------------------------------------------------------------------
    typedef enum logic [2:0] {
        FLIT_HEAD_WR   = 3'b000,   // Write request header
        FLIT_HEAD_RD   = 3'b001,   // Read request header
        FLIT_DATA      = 3'b010,   // Write data payload
        FLIT_RESP_WR   = 3'b011,   // Write response (B channel)
        FLIT_RESP_RD   = 3'b100    // Read response (R channel, carries data)
    } flit_type_t;

    // -----------------------------------------------------------------------
    // Flit structure (fixed width for uniform routing)
    //
    // Total width: 74 bits
    //   [73:71]  flit_type     (3 bits)
    //   [70:69]  src_x, src_y  (1+1 = 2 bits)  — packed as {src_y, src_x}
    //   [68:67]  dst_x, dst_y  (1+1 = 2 bits)  — packed as {dst_y, dst_x}
    //   [66:63]  txn_id        (4 bits)
    //   [62:61]  resp          (2 bits)  — AXI response code
    //   [60:29]  addr          (32 bits)
    //   [28:0]   {padding(25), be(4)} or data_lo(29)
    //
    // For simplicity, use a flat 128-bit flit to carry everything in one
    // shot and avoid multi-flit complexity:
    // -----------------------------------------------------------------------
    parameter int FLIT_W = 128;

    typedef struct packed {
        flit_type_t             flit_type;  // [127:125] 3 bits
        logic [COORD_W-1:0]    src_x;      // [124]     1 bit
        logic [COORD_W-1:0]    src_y;      // [123]     1 bit
        logic [COORD_W-1:0]    dst_x;      // [122]     1 bit
        logic [COORD_W-1:0]    dst_y;      // [121]     1 bit
        logic [TXN_ID_W-1:0]   txn_id;     // [120:117] 4 bits
        logic [1:0]            resp;       // [116:115] 2 bits — AXI resp
        logic [31:0]           addr;       // [114:83]  32 bits
        logic [31:0]           data;       // [82:51]   32 bits
        logic [3:0]            be;         // [50:47]   4 bits — byte enables
        logic [46:0]           reserved;   // [46:0]    padding
    } noc_flit_t;

    // -----------------------------------------------------------------------
    // Router port indices
    // -----------------------------------------------------------------------
    parameter int PORT_LOCAL = 0;
    parameter int PORT_NORTH = 1;
    parameter int PORT_SOUTH = 2;
    parameter int PORT_EAST  = 3;
    parameter int PORT_WEST  = 4;
    parameter int NUM_PORTS  = 5;

    // -----------------------------------------------------------------------
    // Helper: convert flat tile ID to (x, y) coordinates
    // -----------------------------------------------------------------------
    function automatic logic [COORD_W-1:0] tile_to_x(input logic [TILE_ID_W-1:0] tid);
        return tid[0];   // For 2×2: tile0=(0,0), tile1=(1,0), tile2=(0,1), tile3=(1,1)
    endfunction

    function automatic logic [COORD_W-1:0] tile_to_y(input logic [TILE_ID_W-1:0] tid);
        return tid[1];
    endfunction

    function automatic logic [TILE_ID_W-1:0] xy_to_tile(
        input logic [COORD_W-1:0] x, input logic [COORD_W-1:0] y);
        return {y, x};
    endfunction

    // -----------------------------------------------------------------------
    // Address-to-tile mapping
    //
    // For the 4-tile mesh, peripherals are distributed:
    //   Tile 0 (0,0): Boot ROM, UART, Timer, SYSCTRL (peripheral hub)
    //   Tile 1 (1,0): RAM bank 0 (lower 32KB)
    //   Tile 2 (0,1): RAM bank 1 (upper 32KB)
    //   Tile 3 (1,1): (reserved / additional peripherals)
    //
    // Simplified: all peripherals on tile 0, RAM on tile 1
    // -----------------------------------------------------------------------
    function automatic logic [TILE_ID_W-1:0] addr_to_tile(input logic [31:0] addr);
        if (addr >= 32'h8000_0000 && addr < 32'h8001_0000)
            return 2'd1;    // RAM → tile 1
        else
            return 2'd0;    // Everything else (ROM, UART, Timer, SYSCTRL) → tile 0
    endfunction

endpackage