//============================================================================
// control_unit.v — Instruction Decoder / Control Signal Generator
//   - Decodes opcode, funct3, funct7 into pipeline control signals
//   - Purely combinational
//============================================================================

`include "rv32i_defs.vh"

module control_unit (
    input  logic [6:0]  opcode,
    input  logic [2:0]  funct3,
    input  logic [6:0]  funct7,

    // Register file control
    output logic         reg_wr_en,     // Write to rd
    output logic  [1:0]  wb_sel,        // Writeback mux: 0=ALU, 1=MEM, 2=PC+4

    // ALU control
    output logic  [3:0]  alu_op,
    output logic         alu_src_b,     // 0=rs2, 1=immediate

    // Immediate type
    output logic  [2:0]  imm_type,

    // Memory control
    output logic         mem_rd_en,
    output logic         mem_wr_en,
    output logic  [2:0]  mem_funct3,    // Load/store width & sign

    // Branch/Jump control
    output logic         is_branch,
    output logic         is_jal,
    output logic         is_jalr,

    // Misc
    output logic         illegal_inst
);

    always_comb begin
        // Defaults — safe "do nothing" values
        reg_wr_en    = 1'b0;
        wb_sel       = 2'b00;   // ALU result
        alu_op       = `ALU_ADD;
        alu_src_b    = 1'b0;    // rs2
        imm_type     = `IMM_I;
        mem_rd_en    = 1'b0;
        mem_wr_en    = 1'b0;
        mem_funct3   = 3'b000;
        is_branch    = 1'b0;
        is_jal       = 1'b0;
        is_jalr      = 1'b0;
        illegal_inst = 1'b0;

        case (opcode)
            // ----- LUI -----
            `OP_LUI: begin
                reg_wr_en = 1'b1;
                alu_op    = `ALU_PASS_B;
                alu_src_b = 1'b1;
                imm_type  = `IMM_U;
            end

            // ----- AUIPC -----
            `OP_AUIPC: begin
                reg_wr_en = 1'b1;
                alu_op    = `ALU_ADD;
                alu_src_b = 1'b1;   // ALU src_a will be PC (set in datapath)
                imm_type  = `IMM_U;
            end

            // ----- JAL -----
            `OP_JAL: begin
                reg_wr_en = 1'b1;
                wb_sel    = 2'b10;  // PC+4
                is_jal    = 1'b1;
                imm_type  = `IMM_J;
            end

            // ----- JALR -----
            `OP_JALR: begin
                reg_wr_en = 1'b1;
                wb_sel    = 2'b10;  // PC+4
                is_jalr   = 1'b1;
                alu_op    = `ALU_ADD;
                alu_src_b = 1'b1;
                imm_type  = `IMM_I;
            end

            // ----- BRANCH -----
            `OP_BRANCH: begin
                is_branch  = 1'b1;
                imm_type   = `IMM_B;
                // ALU computes rs1 - rs2 for comparison; branch logic is in datapath
                alu_op     = `ALU_SUB;
            end

            // ----- LOAD -----
            `OP_LOAD: begin
                reg_wr_en  = 1'b1;
                wb_sel     = 2'b01; // Memory data
                alu_op     = `ALU_ADD;
                alu_src_b  = 1'b1;
                imm_type   = `IMM_I;
                mem_rd_en  = 1'b1;
                mem_funct3 = funct3;
            end

            // ----- STORE -----
            `OP_STORE: begin
                alu_op     = `ALU_ADD;
                alu_src_b  = 1'b1;
                imm_type   = `IMM_S;
                mem_wr_en  = 1'b1;
                mem_funct3 = funct3;
            end

            // ----- OP-IMM (ADDI, SLTI, etc.) -----
            `OP_OP_IMM: begin
                reg_wr_en = 1'b1;
                alu_src_b = 1'b1;
                imm_type  = `IMM_I;
                case (funct3)
                    `FUNCT3_ADD:  alu_op = `ALU_ADD;   // ADDI
                    `FUNCT3_SLT:  alu_op = `ALU_SLT;   // SLTI
                    `FUNCT3_SLTU: alu_op = `ALU_SLTU;   // SLTIU
                    `FUNCT3_XOR:  alu_op = `ALU_XOR;   // XORI
                    `FUNCT3_OR:   alu_op = `ALU_OR;    // ORI
                    `FUNCT3_AND:  alu_op = `ALU_AND;   // ANDI
                    `FUNCT3_SLL:  alu_op = `ALU_SLL;   // SLLI
                    `FUNCT3_SRL:  alu_op = (funct7[5]) ? `ALU_SRA : `ALU_SRL; // SRLI/SRAI
                    default:      alu_op = `ALU_ADD;
                endcase
            end

            // ----- OP (ADD, SUB, etc.) -----
            `OP_OP: begin
                reg_wr_en = 1'b1;
                case (funct3)
                    `FUNCT3_ADD:  alu_op = (funct7[5]) ? `ALU_SUB : `ALU_ADD;
                    `FUNCT3_SLL:  alu_op = `ALU_SLL;
                    `FUNCT3_SLT:  alu_op = `ALU_SLT;
                    `FUNCT3_SLTU: alu_op = `ALU_SLTU;
                    `FUNCT3_XOR:  alu_op = `ALU_XOR;
                    `FUNCT3_SRL:  alu_op = (funct7[5]) ? `ALU_SRA : `ALU_SRL;
                    `FUNCT3_OR:   alu_op = `ALU_OR;
                    `FUNCT3_AND:  alu_op = `ALU_AND;
                    default:      alu_op = `ALU_ADD;
                endcase
            end

            // ----- FENCE (treat as NOP for now) -----
            `OP_FENCE: begin
                // No operation — ordering is trivially satisfied in-order
            end

            // ----- SYSTEM (ECALL, EBREAK — treat as NOP) -----
            `OP_SYSTEM: begin
                // Minimal: no CSR support, ECALL/EBREAK are NOPs
            end

            default: begin
                illegal_inst = 1'b1;
            end
        endcase
    end

endmodule