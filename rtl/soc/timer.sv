//============================================================================
// timer.sv — RISC-V Machine Timer (mtime / mtimecmp)
//
// Implements the RISC-V privileged specification timer:
//   - 64-bit free-running counter (mtime)
//   - 64-bit compare register (mtimecmp)
//   - Timer interrupt when mtime >= mtimecmp
//   - Enable/disable control
//
// Registers (32-bit access to 64-bit values):
//   0x00 MTIME_LO     RW — mtime[31:0]
//   0x04 MTIME_HI     RW — mtime[63:32]
//   0x08 MTIMECMP_LO  RW — mtimecmp[31:0]
//   0x0C MTIMECMP_HI  RW — mtimecmp[63:32]
//   0x10 CTRL         RW — [0] timer enable
//============================================================================

module timer
    import soc_pkg::*;
(
    input  logic        clk,
    input  logic        rst_n,

    // Register bus interface
    input  logic [31:0] addr,
    input  logic [31:0] wdata,
    input  logic        rd_en,
    input  logic        wr_en,
    input  logic [3:0]  be,
    output logic [31:0] rdata,
    output logic        valid,

    // Timer interrupt output
    output logic        irq_timer
);

    // -----------------------------------------------------------------------
    // Registers
    // -----------------------------------------------------------------------
    logic [63:0] mtime;
    logic [63:0] mtimecmp;
    logic        timer_en;

    logic [7:0] reg_addr;
    assign reg_addr = addr[7:0];

    // -----------------------------------------------------------------------
    // Timer counter
    // -----------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mtime <= '0;
        end else if (wr_en && (reg_addr == TIMER_MTIME_LO)) begin
            // Software write to mtime low — merge with byte enables
            if (be[0]) mtime[7:0]   <= wdata[7:0];
            if (be[1]) mtime[15:8]  <= wdata[15:8];
            if (be[2]) mtime[23:16] <= wdata[23:16];
            if (be[3]) mtime[31:24] <= wdata[31:24];
        end else if (wr_en && (reg_addr == TIMER_MTIME_HI)) begin
            if (be[0]) mtime[39:32] <= wdata[7:0];
            if (be[1]) mtime[47:40] <= wdata[15:8];
            if (be[2]) mtime[55:48] <= wdata[23:16];
            if (be[3]) mtime[63:56] <= wdata[31:24];
        end else if (timer_en) begin
            mtime <= mtime + 64'd1;
        end
    end

    // -----------------------------------------------------------------------
    // Compare register
    // -----------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mtimecmp <= 64'hFFFF_FFFF_FFFF_FFFF; // Max value = no spurious IRQ
        end else if (wr_en && (reg_addr == TIMER_MTIMECMP_LO)) begin
            if (be[0]) mtimecmp[7:0]   <= wdata[7:0];
            if (be[1]) mtimecmp[15:8]  <= wdata[15:8];
            if (be[2]) mtimecmp[23:16] <= wdata[23:16];
            if (be[3]) mtimecmp[31:24] <= wdata[31:24];
        end else if (wr_en && (reg_addr == TIMER_MTIMECMP_HI)) begin
            if (be[0]) mtimecmp[39:32] <= wdata[7:0];
            if (be[1]) mtimecmp[47:40] <= wdata[15:8];
            if (be[2]) mtimecmp[55:48] <= wdata[23:16];
            if (be[3]) mtimecmp[63:56] <= wdata[31:24];
        end
    end

    // -----------------------------------------------------------------------
    // Control register
    // -----------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            timer_en <= 1'b0;
        else if (wr_en && (reg_addr == TIMER_CTRL) && be[0])
            timer_en <= wdata[0];
    end

    // -----------------------------------------------------------------------
    // Interrupt: level-sensitive, asserted while mtime >= mtimecmp
    // -----------------------------------------------------------------------
    assign irq_timer = timer_en && (mtime >= mtimecmp);

    // Combinational read
    always_comb begin
        valid = rd_en;
        case (reg_addr)
            TIMER_MTIME_LO:    rdata = mtime[31:0];
            TIMER_MTIME_HI:    rdata = mtime[63:32];
            TIMER_MTIMECMP_LO: rdata = mtimecmp[31:0];
            TIMER_MTIMECMP_HI: rdata = mtimecmp[63:32];
            TIMER_CTRL:        rdata = {31'b0, timer_en};
            default:           rdata = '0;
        endcase
    end

endmodule