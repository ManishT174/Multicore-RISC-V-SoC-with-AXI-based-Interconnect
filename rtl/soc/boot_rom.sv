//============================================================================
// boot_rom.sv — Boot ROM
//
// - Single-cycle synchronous read
// - Read-only (writes are silently ignored)
// - Contents loaded from MEM_INIT_FILE at elaboration
// - 16 KB default (4096 x 32-bit words)
//============================================================================

module boot_rom
    import soc_pkg::*;
#(
    parameter int    DEPTH         = 4096,       // Number of 32-bit words
    parameter        MEM_INIT_FILE = ""          // Path to $readmemh file
)(
    input  logic        clk,
    input  logic        rst_n,

    // Memory bus interface
    input  logic [31:0] addr,       // Byte address (word-aligned access)
    input  logic        rd_en,
    output logic [31:0] rdata,
    output logic        valid
);

    localparam int ADDR_BITS = $clog2(DEPTH);

    // Storage
    logic [31:0] mem [0:DEPTH-1];

    // Word address
    logic [ADDR_BITS-1:0] word_addr;
    assign word_addr = addr[ADDR_BITS+1:2]; // Drop byte offset bits

    // Combinational read (0-cycle latency)
    assign rdata = mem[word_addr];
    assign valid = rd_en;

    // Memory initialization
    initial begin
        // Zero-fill first
        for (int i = 0; i < DEPTH; i++)
            mem[i] = 32'h0000_0013; // NOP (addi x0, x0, 0)

        if (MEM_INIT_FILE != "")
            $readmemh(MEM_INIT_FILE, mem);
    end

endmodule