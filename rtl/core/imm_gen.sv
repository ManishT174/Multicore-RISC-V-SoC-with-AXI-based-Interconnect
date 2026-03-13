//============================================================================
// imm_gen.v — Immediate Generator
//   - Extracts and sign-extends immediates for all RV32I formats
//   - Purely combinational
//============================================================================

`include "rv32i_defs.vh"

module imm_gen (
    input  logic [2:0]  imm_type,
    input  logic [31:0] inst,
    output logic  [31:0] imm
);

    always_comb begin
        case (imm_type)
            // I-type: inst[31:20]
            `IMM_I: imm = {{20{inst[31]}}, inst[31:20]};

            // S-type: {inst[31:25], inst[11:7]}
            `IMM_S: imm = {{20{inst[31]}}, inst[31:25], inst[11:7]};

            // B-type: {inst[31], inst[7], inst[30:25], inst[11:8], 1'b0}
            `IMM_B: imm = {{19{inst[31]}}, inst[31], inst[7],
                           inst[30:25], inst[11:8], 1'b0};

            // U-type: {inst[31:12], 12'b0}
            `IMM_U: imm = {inst[31:12], 12'd0};

            // J-type: {inst[31], inst[19:12], inst[20], inst[30:21], 1'b0}
            `IMM_J: imm = {{11{inst[31]}}, inst[31], inst[19:12],
                           inst[20], inst[30:21], 1'b0};

            default: imm = 32'd0;
        endcase
    end

endmodule