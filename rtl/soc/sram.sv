//============================================================================
// sram.sv — Synchronous SRAM with Byte Enables
//
// - Single-cycle read and write
// - 4-bit byte-enable for sub-word writes
// - 64 KB default (16384 x 32-bit words)
// - Optional initialization from hex file
//============================================================================

module sram
    import soc_pkg::*;
#(
    parameter int    DEPTH         = 16384,      // Number of 32-bit words
    parameter        MEM_INIT_FILE = ""
)(
    input  logic        clk,
    input  logic        rst_n,

    // Memory bus interface
    input  logic [31:0] addr,       // Byte address
    input  logic [31:0] wdata,
    input  logic        rd_en,
    input  logic        wr_en,
    input  logic [3:0]  be,         // Byte enables
    output logic [31:0] rdata,
    output logic        valid
);

    localparam int ADDR_BITS = $clog2(DEPTH);

    // Storage — 4 byte-wide banks for byte-enable writes
    logic [7:0] mem_b0 [0:DEPTH-1]; // Byte 0 (bits [7:0])
    logic [7:0] mem_b1 [0:DEPTH-1]; // Byte 1 (bits [15:8])
    logic [7:0] mem_b2 [0:DEPTH-1]; // Byte 2 (bits [23:16])
    logic [7:0] mem_b3 [0:DEPTH-1]; // Byte 3 (bits [31:24])

    // Word address
    logic [ADDR_BITS-1:0] word_addr;
    assign word_addr = addr[ADDR_BITS+1:2];

    // Synchronous write
    always_ff @(posedge clk) begin
        if (wr_en) begin
            if (be[0]) mem_b0[word_addr] <= wdata[7:0];
            if (be[1]) mem_b1[word_addr] <= wdata[15:8];
            if (be[2]) mem_b2[word_addr] <= wdata[23:16];
            if (be[3]) mem_b3[word_addr] <= wdata[31:24];
        end
    end

    // Combinational read (0-cycle latency, matching core expectation)
    assign rdata = {mem_b3[word_addr], mem_b2[word_addr],
                    mem_b1[word_addr], mem_b0[word_addr]};
    assign valid = rd_en || wr_en;

    // Memory initialization
    initial begin
        for (int i = 0; i < DEPTH; i++) begin
            mem_b0[i] = 8'h00;
            mem_b1[i] = 8'h00;
            mem_b2[i] = 8'h00;
            mem_b3[i] = 8'h00;
        end

        if (MEM_INIT_FILE != "") begin
            // Load 32-bit words, then split into byte banks
            logic [31:0] temp_mem [0:DEPTH-1];
            $readmemh(MEM_INIT_FILE, temp_mem);
            for (int i = 0; i < DEPTH; i++) begin
                mem_b0[i] = temp_mem[i][7:0];
                mem_b1[i] = temp_mem[i][15:8];
                mem_b2[i] = temp_mem[i][23:16];
                mem_b3[i] = temp_mem[i][31:24];
            end
        end
    end

endmodule