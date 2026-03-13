//============================================================================
// branch_unit.v — Branch Condition Evaluator
//   - Evaluates all RV32I branch conditions
//   - Separated from ALU to avoid polluting the ALU critical path
//============================================================================

`include "rv32i_defs.vh"

module branch_unit (
    input  logic [2:0]  funct3,
    input  logic [31:0] rs1_data,
    input  logic [31:0] rs2_data,
    output logic         branch_taken
);

    logic        eq   = (rs1_data == rs2_data);
    logic        lt   = ($signed(rs1_data) < $signed(rs2_data));
    logic        ltu  = (rs1_data < rs2_data);

    always_comb begin
        case (funct3)
            `FUNCT3_BEQ:  branch_taken =  eq;
            `FUNCT3_BNE:  branch_taken = !eq;
            `FUNCT3_BLT:  branch_taken =  lt;
            `FUNCT3_BGE:  branch_taken = !lt;
            `FUNCT3_BLTU: branch_taken =  ltu;
            `FUNCT3_BGEU: branch_taken = !ltu;
            default:       branch_taken = 1'b0;
        endcase
    end

endmodule