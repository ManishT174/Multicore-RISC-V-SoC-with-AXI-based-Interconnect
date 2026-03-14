//============================================================================
// mesh_2x2.sv — 2×2 Mesh Network Topology
//
// Tile layout:
//
//   (0,1) ──── (1,1)     Row 1 (North)
//     │          │
//     │          │
//   (0,0) ──── (1,0)     Row 0 (South)
//
// Connections:
//   (0,0) East  ↔ (1,0) West
//   (0,1) East  ↔ (1,1) West
//   (0,0) North ↔ (0,1) South
//   (1,0) North ↔ (1,1) South
//
// Boundary ports (mesh edges) are tied off with valid=0, ready=1.
//
// Each tile's Local port is exposed for connection to the
// AXI-NoC bridge / core.
//============================================================================

module mesh_2x2
    import noc_pkg::*;
#(
    parameter int FIFO_DEPTH = 4
)(
    input  logic clk,
    input  logic rst_n,

    // ---- Local ports for each tile (exposed to AXI-NoC bridges) ----
    // Tile 0 (0,0)
    input  logic [FLIT_W-1:0] t0_local_in_data,
    input  logic               t0_local_in_valid,
    output logic               t0_local_in_ready,
    output logic [FLIT_W-1:0] t0_local_out_data,
    output logic               t0_local_out_valid,
    input  logic               t0_local_out_ready,

    // Tile 1 (1,0)
    input  logic [FLIT_W-1:0] t1_local_in_data,
    input  logic               t1_local_in_valid,
    output logic               t1_local_in_ready,
    output logic [FLIT_W-1:0] t1_local_out_data,
    output logic               t1_local_out_valid,
    input  logic               t1_local_out_ready,

    // Tile 2 (0,1)
    input  logic [FLIT_W-1:0] t2_local_in_data,
    input  logic               t2_local_in_valid,
    output logic               t2_local_in_ready,
    output logic [FLIT_W-1:0] t2_local_out_data,
    output logic               t2_local_out_valid,
    input  logic               t2_local_out_ready,

    // Tile 3 (1,1)
    input  logic [FLIT_W-1:0] t3_local_in_data,
    input  logic               t3_local_in_valid,
    output logic               t3_local_in_ready,
    output logic [FLIT_W-1:0] t3_local_out_data,
    output logic               t3_local_out_valid,
    input  logic               t3_local_out_ready
);

    // -----------------------------------------------------------------------
    // Inter-router link wires
    //
    // Naming: r{src}_to_r{dst}_{direction}
    // Each link has: data, valid (src→dst), ready (dst→src)
    // -----------------------------------------------------------------------

    // East-West links (row 0): R00 East ↔ R10 West
    logic [FLIT_W-1:0] r00_east_data, r10_west_data;
    logic               r00_east_valid, r10_west_valid;
    logic               r00_east_ready, r10_west_ready;

    // East-West links (row 1): R01 East ↔ R11 West
    logic [FLIT_W-1:0] r01_east_data, r11_west_data;
    logic               r01_east_valid, r11_west_valid;
    logic               r01_east_ready, r11_west_ready;

    // North-South links (col 0): R00 North ↔ R01 South
    logic [FLIT_W-1:0] r00_north_data, r01_south_data;
    logic               r00_north_valid, r01_south_valid;
    logic               r00_north_ready, r01_south_ready;

    // North-South links (col 1): R10 North ↔ R11 South
    logic [FLIT_W-1:0] r10_north_data, r11_south_data;
    logic               r10_north_valid, r11_south_valid;
    logic               r10_north_ready, r11_south_ready;

    // -----------------------------------------------------------------------
    // Router (0,0) — Tile 0
    // -----------------------------------------------------------------------
    mesh_router #(.MY_X(0), .MY_Y(0), .FIFO_DEPTH(FIFO_DEPTH)) r00 (
        .clk(clk), .rst_n(rst_n),
        // Local
        .local_in_data(t0_local_in_data),   .local_in_valid(t0_local_in_valid),
        .local_in_ready(t0_local_in_ready),
        .local_out_data(t0_local_out_data), .local_out_valid(t0_local_out_valid),
        .local_out_ready(t0_local_out_ready),
        // North → connects to R01 South
        .north_in_data(r01_south_data),     .north_in_valid(r01_south_valid),
        .north_in_ready(r01_south_ready),
        .north_out_data(r00_north_data),    .north_out_valid(r00_north_valid),
        .north_out_ready(r00_north_ready),
        // South → boundary (tied off)
        .south_in_data('0),                 .south_in_valid(1'b0),
        .south_in_ready(),
        .south_out_data(),                  .south_out_valid(),
        .south_out_ready(1'b1),
        // East → connects to R10 West
        .east_in_data(r10_west_data),       .east_in_valid(r10_west_valid),
        .east_in_ready(r10_west_ready),
        .east_out_data(r00_east_data),      .east_out_valid(r00_east_valid),
        .east_out_ready(r00_east_ready),
        // West → boundary (tied off)
        .west_in_data('0),                  .west_in_valid(1'b0),
        .west_in_ready(),
        .west_out_data(),                   .west_out_valid(),
        .west_out_ready(1'b1)
    );

    // -----------------------------------------------------------------------
    // Router (1,0) — Tile 1
    // -----------------------------------------------------------------------
    mesh_router #(.MY_X(1), .MY_Y(0), .FIFO_DEPTH(FIFO_DEPTH)) r10 (
        .clk(clk), .rst_n(rst_n),
        // Local
        .local_in_data(t1_local_in_data),   .local_in_valid(t1_local_in_valid),
        .local_in_ready(t1_local_in_ready),
        .local_out_data(t1_local_out_data), .local_out_valid(t1_local_out_valid),
        .local_out_ready(t1_local_out_ready),
        // North → connects to R11 South
        .north_in_data(r11_south_data),     .north_in_valid(r11_south_valid),
        .north_in_ready(r11_south_ready),
        .north_out_data(r10_north_data),    .north_out_valid(r10_north_valid),
        .north_out_ready(r10_north_ready),
        // South → boundary
        .south_in_data('0),                 .south_in_valid(1'b0),
        .south_in_ready(),
        .south_out_data(),                  .south_out_valid(),
        .south_out_ready(1'b1),
        // East → boundary
        .east_in_data('0),                  .east_in_valid(1'b0),
        .east_in_ready(),
        .east_out_data(),                   .east_out_valid(),
        .east_out_ready(1'b1),
        // West → connects to R00 East
        .west_in_data(r00_east_data),       .west_in_valid(r00_east_valid),
        .west_in_ready(r00_east_ready),
        .west_out_data(r10_west_data),      .west_out_valid(r10_west_valid),
        .west_out_ready(r10_west_ready)
    );

    // -----------------------------------------------------------------------
    // Router (0,1) — Tile 2
    // -----------------------------------------------------------------------
    mesh_router #(.MY_X(0), .MY_Y(1), .FIFO_DEPTH(FIFO_DEPTH)) r01 (
        .clk(clk), .rst_n(rst_n),
        // Local
        .local_in_data(t2_local_in_data),   .local_in_valid(t2_local_in_valid),
        .local_in_ready(t2_local_in_ready),
        .local_out_data(t2_local_out_data), .local_out_valid(t2_local_out_valid),
        .local_out_ready(t2_local_out_ready),
        // North → boundary
        .north_in_data('0),                 .north_in_valid(1'b0),
        .north_in_ready(),
        .north_out_data(),                  .north_out_valid(),
        .north_out_ready(1'b1),
        // South → connects to R00 North
        .south_in_data(r00_north_data),     .south_in_valid(r00_north_valid),
        .south_in_ready(r00_north_ready),
        .south_out_data(r01_south_data),    .south_out_valid(r01_south_valid),
        .south_out_ready(r01_south_ready),
        // East → connects to R11 West
        .east_in_data(r11_west_data),       .east_in_valid(r11_west_valid),
        .east_in_ready(r11_west_ready),
        .east_out_data(r01_east_data),      .east_out_valid(r01_east_valid),
        .east_out_ready(r01_east_ready),
        // West → boundary
        .west_in_data('0),                  .west_in_valid(1'b0),
        .west_in_ready(),
        .west_out_data(),                   .west_out_valid(),
        .west_out_ready(1'b1)
    );

    // -----------------------------------------------------------------------
    // Router (1,1) — Tile 3
    // -----------------------------------------------------------------------
    mesh_router #(.MY_X(1), .MY_Y(1), .FIFO_DEPTH(FIFO_DEPTH)) r11 (
        .clk(clk), .rst_n(rst_n),
        // Local
        .local_in_data(t3_local_in_data),   .local_in_valid(t3_local_in_valid),
        .local_in_ready(t3_local_in_ready),
        .local_out_data(t3_local_out_data), .local_out_valid(t3_local_out_valid),
        .local_out_ready(t3_local_out_ready),
        // North → boundary
        .north_in_data('0),                 .north_in_valid(1'b0),
        .north_in_ready(),
        .north_out_data(),                  .north_out_valid(),
        .north_out_ready(1'b1),
        // South → connects to R10 North
        .south_in_data(r10_north_data),     .south_in_valid(r10_north_valid),
        .south_in_ready(r10_north_ready),
        .south_out_data(r11_south_data),    .south_out_valid(r11_south_valid),
        .south_out_ready(r11_south_ready),
        // East → boundary
        .east_in_data('0),                  .east_in_valid(1'b0),
        .east_in_ready(),
        .east_out_data(),                   .east_out_valid(),
        .east_out_ready(1'b1),
        // West → connects to R01 East
        .west_in_data(r01_east_data),       .west_in_valid(r01_east_valid),
        .west_in_ready(r01_east_ready),
        .west_out_data(r11_west_data),      .west_out_valid(r11_west_valid),
        .west_out_ready(r11_west_ready)
    );

endmodule