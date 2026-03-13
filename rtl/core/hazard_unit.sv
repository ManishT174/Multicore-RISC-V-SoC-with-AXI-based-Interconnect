//============================================================================
// hazard_unit.v — Hazard Detection & Forwarding Control
//   - Data forwarding: EX/MEM → EX, MEM/WB → EX
//   - Load-use stall: 1-cycle bubble when EX stage has a load and
//     the next instruction reads the loaded register
//   - Branch/jump flush: kills IF/ID when a branch is taken or jump executes
//============================================================================

`include "rv32i_defs.vh"

module hazard_unit (
    // Source registers in ID/EX stage (the instruction about to enter EX)
    input  logic [4:0]  id_ex_rs1,
    input  logic [4:0]  id_ex_rs2,

    // Destination register in EX/MEM stage
    input  logic [4:0]  ex_mem_rd,
    input  logic        ex_mem_reg_wr_en,
    input  logic        ex_mem_mem_rd_en,   // Is EX/MEM a load?

    // Destination register in MEM/WB stage
    input  logic [4:0]  mem_wb_rd,
    input  logic        mem_wb_reg_wr_en,

    // Source registers in IF/ID stage (for load-use detection)
    input  logic [4:0]  if_id_rs1,
    input  logic [4:0]  if_id_rs2,

    // Load in ID/EX (for load-use: instruction currently in EX is a load)
    input  logic [4:0]  id_ex_rd,
    input  logic        id_ex_mem_rd_en,

    // Branch/jump taken
    input  logic        branch_taken,
    input  logic        jump_taken,

    // Forwarding mux selects for EX stage operands
    output logic  [1:0]  fwd_a,    // Forwarding for ALU operand A
    output logic  [1:0]  fwd_b,    // Forwarding for ALU operand B

    // Pipeline control
    output logic        stall_if,     // Freeze PC and IF/ID register
    output logic        stall_id,     // Freeze ID/EX register
    output logic        flush_id,     // Insert bubble in ID/EX
    output logic        flush_ex      // Insert bubble in EX/MEM (not typically needed)
);

    // -----------------------------------------------------------------------
    // Data Forwarding Logic
    //   Priority: EX/MEM (most recent) over MEM/WB
    // -----------------------------------------------------------------------
    always_comb begin
        // Forward A (rs1)
        if (ex_mem_reg_wr_en && (ex_mem_rd != 5'd0) && (ex_mem_rd == id_ex_rs1))
            fwd_a = `FWD_EX_MEM;
        else if (mem_wb_reg_wr_en && (mem_wb_rd != 5'd0) && (mem_wb_rd == id_ex_rs1))
            fwd_a = `FWD_MEM_WB;
        else
            fwd_a = `FWD_NONE;

        // Forward B (rs2)
        if (ex_mem_reg_wr_en && (ex_mem_rd != 5'd0) && (ex_mem_rd == id_ex_rs2))
            fwd_b = `FWD_EX_MEM;
        else if (mem_wb_reg_wr_en && (mem_wb_rd != 5'd0) && (mem_wb_rd == id_ex_rs2))
            fwd_b = `FWD_MEM_WB;
        else
            fwd_b = `FWD_NONE;
    end

    // -----------------------------------------------------------------------
    // Load-Use Hazard Detection
    //   If the instruction in ID/EX is a LOAD and the instruction in IF/ID
    //   reads the load's destination, we must stall for 1 cycle.
    // -----------------------------------------------------------------------
    logic load_use_hazard = id_ex_mem_rd_en && (id_ex_rd != 5'd0) &&
                           ((id_ex_rd == if_id_rs1) || (id_ex_rd == if_id_rs2));

    // -----------------------------------------------------------------------
    // Pipeline Control Signals
    // -----------------------------------------------------------------------
    // Stall IF and ID on load-use hazard
    assign stall_if = load_use_hazard;
    assign stall_id = load_use_hazard;

    // Flush IF/ID on branch/jump taken (kill the wrongly fetched instruction)
    // Also flush ID/EX on load-use (insert a NOP bubble)
    assign flush_id = branch_taken || jump_taken;
    assign flush_ex = load_use_hazard;

endmodule