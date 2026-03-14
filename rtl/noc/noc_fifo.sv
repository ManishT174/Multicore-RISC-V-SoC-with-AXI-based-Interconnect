//============================================================================
// noc_fifo.sv — Synchronous FIFO for NoC Router Ports
//
// - Parameterized width and depth
// - Valid/ready handshake on both sides
// - Registered output for timing closure
// - Full/empty flags derived from pointer comparison
//============================================================================

module noc_fifo #(
    parameter int WIDTH = 128,
    parameter int DEPTH = 4
)(
    input  logic             clk,
    input  logic             rst_n,

    // Input side
    input  logic [WIDTH-1:0] din,
    input  logic             din_valid,
    output logic             din_ready,   // Not full

    // Output side
    output logic [WIDTH-1:0] dout,
    output logic             dout_valid,  // Not empty
    input  logic             dout_ready
);

    localparam int PTR_W = $clog2(DEPTH) + 1;  // Extra bit for full/empty

    logic [WIDTH-1:0] mem [0:DEPTH-1];
    logic [PTR_W-1:0] wr_ptr, rd_ptr;

    wire [PTR_W-2:0] wr_addr = wr_ptr[PTR_W-2:0];
    wire [PTR_W-2:0] rd_addr = rd_ptr[PTR_W-2:0];

    wire full  = (wr_ptr[PTR_W-1] != rd_ptr[PTR_W-1]) &&
                 (wr_addr == rd_addr);
    wire empty = (wr_ptr == rd_ptr);

    assign din_ready  = !full;
    assign dout_valid = !empty;
    assign dout       = mem[rd_addr];

    // Write
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= '0;
        end else if (din_valid && din_ready) begin
            mem[wr_addr] <= din;
            wr_ptr <= wr_ptr + 1;
        end
    end

    // Read
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_ptr <= '0;
        end else if (dout_valid && dout_ready) begin
            rd_ptr <= rd_ptr + 1;
        end
    end

endmodule