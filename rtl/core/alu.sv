//============================================================================
// alu.sv — Arithmetic Logic Unit
//   - Combinational: result available same cycle
//   - Supports all RV32I operations
//============================================================================

`include "rv32i_defs.vh"

module alu (
    input logic [3:0]  alu_op,
    input logic [31:0] op_a,
    input logic [31:0] op_b,
    output logic  [31:0] result,
    output logic        zero       // result == 0, useful for branches
);

    assign zero = (result == 32'd0);

    always_comb begin
        case (alu_op)
            `ALU_ADD:    result = op_a + op_b;
            `ALU_SUB:    result = op_a - op_b;
            `ALU_SLL:    result = op_a << op_b[4:0];
            `ALU_SLT:    result = ($signed(op_a) < $signed(op_b)) ? 32'd1 : 32'd0;
            `ALU_SLTU:   result = (op_a < op_b) ? 32'd1 : 32'd0;
            `ALU_XOR:    result = op_a ^ op_b;
            `ALU_SRL:    result = op_a >> op_b[4:0];
            `ALU_SRA:    result = $signed(op_a) >>> op_b[4:0];
            `ALU_OR:     result = op_a | op_b;
            `ALU_AND:    result = op_a & op_b;
            `ALU_PASS_B: result = op_b;  // LUI: pass upper immediate
            default:     result = 32'd0;
        endcase
    end

endmodule