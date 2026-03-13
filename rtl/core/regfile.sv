//============================================================================
// regfile.v — 32x32 Register File
//   - 2 asynchronous read ports (combinational)
//   - 1 synchronous write port (posedge clk)
//   - x0 hardwired to 0
//============================================================================

module regfile (
    input  logic        clk,
    input  logic        rst_n,

    // Read port A
    input  logic [4:0]  rs1_addr,
    output logic [31:0] rs1_data,

    // Read port B
    input  logic [4:0]  rs2_addr,
    output logic [31:0] rs2_data,

    // Write port
    input  logic        wr_en,
    input  logic [4:0]  rd_addr,
    input  logic [31:0] rd_data
);

    reg [31:0] regs [0:31];

    // Combinational reads with write-through
    // If reading the same register being written, forward the write data
    assign rs1_data = (rs1_addr == 5'd0) ? 32'd0 :
                      (wr_en && (rs1_addr == rd_addr)) ? rd_data :
                      regs[rs1_addr];

    assign rs2_data = (rs2_addr == 5'd0) ? 32'd0 :
                      (wr_en && (rs2_addr == rd_addr)) ? rd_data :
                      regs[rs2_addr];

    // Synchronous write
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 32; i = i + 1)
                regs[i] <= 32'd0;
        end else if (wr_en && (rd_addr != 5'd0)) begin
            regs[rd_addr] <= rd_data;
        end
    end

endmodule