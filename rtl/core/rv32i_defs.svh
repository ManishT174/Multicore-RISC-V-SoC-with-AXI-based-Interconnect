//============================================================================
// rv32i_defs.vh — RV32I ISA Definitions
//============================================================================

`ifndef RV32I_DEFS_VH
`define RV32I_DEFS_VH

// ---------------------------------------------------------------------------
// Opcodes (inst[6:0])
// ---------------------------------------------------------------------------
`define OP_LUI       7'b0110111
`define OP_AUIPC     7'b0010111
`define OP_JAL       7'b1101111
`define OP_JALR      7'b1100111
`define OP_BRANCH    7'b1100011
`define OP_LOAD      7'b0000011
`define OP_STORE     7'b0100011
`define OP_OP_IMM    7'b0010011
`define OP_OP        7'b0110011
`define OP_FENCE     7'b0001111
`define OP_SYSTEM    7'b1110011

// ---------------------------------------------------------------------------
// ALU Function Codes (funct3)
// ---------------------------------------------------------------------------
`define FUNCT3_ADD   3'b000
`define FUNCT3_SLL   3'b001
`define FUNCT3_SLT   3'b010
`define FUNCT3_SLTU  3'b011
`define FUNCT3_XOR   3'b100
`define FUNCT3_SRL   3'b101
`define FUNCT3_OR    3'b110
`define FUNCT3_AND   3'b111

// ---------------------------------------------------------------------------
// Branch Function Codes (funct3)
// ---------------------------------------------------------------------------
`define FUNCT3_BEQ   3'b000
`define FUNCT3_BNE   3'b001
`define FUNCT3_BLT   3'b100
`define FUNCT3_BGE   3'b101
`define FUNCT3_BLTU  3'b110
`define FUNCT3_BGEU  3'b111

// ---------------------------------------------------------------------------
// Load/Store Function Codes (funct3)
// ---------------------------------------------------------------------------
`define FUNCT3_LB    3'b000
`define FUNCT3_LH    3'b001
`define FUNCT3_LW    3'b010
`define FUNCT3_LBU   3'b100
`define FUNCT3_LHU   3'b101
`define FUNCT3_SB    3'b000
`define FUNCT3_SH    3'b001
`define FUNCT3_SW    3'b010

// ---------------------------------------------------------------------------
// ALU Operation Encoding (internal, not ISA)
// ---------------------------------------------------------------------------
`define ALU_ADD      4'b0000
`define ALU_SUB      4'b0001
`define ALU_SLL      4'b0010
`define ALU_SLT      4'b0011
`define ALU_SLTU     4'b0100
`define ALU_XOR      4'b0101
`define ALU_SRL      4'b0110
`define ALU_SRA      4'b0111
`define ALU_OR       4'b1000
`define ALU_AND      4'b1001
`define ALU_PASS_B   4'b1010  // Pass operand B through (for LUI)

// ---------------------------------------------------------------------------
// Immediate Type Encoding (internal)
// ---------------------------------------------------------------------------
`define IMM_I        3'b000
`define IMM_S        3'b001
`define IMM_B        3'b010
`define IMM_U        3'b011
`define IMM_J        3'b100

// ---------------------------------------------------------------------------
// Forwarding Source Select
// ---------------------------------------------------------------------------
`define FWD_NONE     2'b00
`define FWD_EX_MEM   2'b01
`define FWD_MEM_WB   2'b10

`endif
