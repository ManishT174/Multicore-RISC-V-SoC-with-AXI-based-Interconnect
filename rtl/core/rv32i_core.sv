//============================================================================
// rv32i_core.v — 5-Stage Pipelined RV32I Processor Core
//
// Pipeline:  IF → ID → EX → MEM → WB
//
// Features:
//   - Full data forwarding (EX→EX, MEM→EX)
//   - Load-use hazard stall (1-cycle bubble)
//   - Branch resolution in EX stage with 2-cycle flush penalty
//   - Harvard memory interface (separate I-mem and D-mem ports)
//   - Parameterized HART_ID for multi-core support
//
// Memory Interface:
//   - Instruction port: imem_addr, imem_rdata, imem_valid
//   - Data port: dmem_addr, dmem_wdata, dmem_rdata, dmem_rd, dmem_wr,
//                dmem_be, dmem_valid
//============================================================================

`include "rv32i_defs.vh"

module rv32i_core #(
    parameter HART_ID   = 0,
    parameter RESET_PC  = 32'h0000_0000
)(
    input  logic        clk,
    input  logic        rst_n,

    // Instruction memory port
    output logic [31:0] imem_addr,
    input  logic [31:0] imem_rdata,
    output logic        imem_req,
    input  logic        imem_valid,

    // Data memory port
    output logic [31:0] dmem_addr,
    output logic [31:0] dmem_wdata,
    input  logic [31:0] dmem_rdata,
    output logic        dmem_rd,
    output logic        dmem_wr,
    output logic [3:0]  dmem_be,
    input  logic        dmem_valid
);

    // -----------------------------------------------------------------------
    // Wires from hazard unit
    // -----------------------------------------------------------------------
    wire [1:0]  fwd_a, fwd_b;
    wire        stall_if, stall_id;
    wire        flush_id, flush_ex;

    // -----------------------------------------------------------------------
    // Wires for branch/jump resolution
    // -----------------------------------------------------------------------
    wire        branch_taken_ex;
    wire        jump_taken_ex;
    wire [31:0] branch_target_ex;

    // =====================================================================
    //  STAGE 1: INSTRUCTION FETCH (IF)
    // =====================================================================
    reg  [31:0] pc_reg;
    wire [31:0] pc_next;
    wire        pc_we = !stall_if && imem_valid;

    // PC mux: branch/jump target or sequential
    assign pc_next = (branch_taken_ex || jump_taken_ex) ? branch_target_ex :
                     pc_reg + 32'd4;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            pc_reg <= RESET_PC;
        else if (pc_we)
            pc_reg <= pc_next;
    end

    assign imem_addr = pc_reg;
    assign imem_req  = !stall_if;

    // =====================================================================
    //  IF/ID Pipeline Register
    // =====================================================================
    reg [31:0] if_id_pc;
    reg [31:0] if_id_inst;
    reg        if_id_valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            if_id_pc    <= 32'd0;
            if_id_inst  <= 32'h0000_0013; // NOP (addi x0, x0, 0)
            if_id_valid <= 1'b0;
        end else if (flush_id) begin
            // Kill fetched instruction on branch/jump
            if_id_pc    <= 32'd0;
            if_id_inst  <= 32'h0000_0013;
            if_id_valid <= 1'b0;
        end else if (!stall_id && imem_valid) begin
            if_id_pc    <= pc_reg;
            if_id_inst  <= imem_rdata;
            if_id_valid <= 1'b1;
        end
    end

    // =====================================================================
    //  STAGE 2: INSTRUCTION DECODE (ID)
    // =====================================================================

    // Instruction field extraction
    wire [6:0]  id_opcode = if_id_inst[6:0];
    wire [4:0]  id_rd     = if_id_inst[11:7];
    wire [2:0]  id_funct3 = if_id_inst[14:12];
    wire [4:0]  id_rs1    = if_id_inst[19:15];
    wire [4:0]  id_rs2    = if_id_inst[24:20];
    wire [6:0]  id_funct7 = if_id_inst[31:25];

    // Control signals from decoder
    wire        id_reg_wr_en;
    wire [1:0]  id_wb_sel;
    wire [3:0]  id_alu_op;
    wire        id_alu_src_b;
    wire [2:0]  id_imm_type;
    wire        id_mem_rd_en;
    wire        id_mem_wr_en;
    wire [2:0]  id_mem_funct3;
    wire        id_is_branch;
    wire        id_is_jal;
    wire        id_is_jalr;
    wire        id_illegal_inst;

    control_unit u_ctrl (
        .opcode       (id_opcode),
        .funct3       (id_funct3),
        .funct7       (id_funct7),
        .reg_wr_en    (id_reg_wr_en),
        .wb_sel       (id_wb_sel),
        .alu_op       (id_alu_op),
        .alu_src_b    (id_alu_src_b),
        .imm_type     (id_imm_type),
        .mem_rd_en    (id_mem_rd_en),
        .mem_wr_en    (id_mem_wr_en),
        .mem_funct3   (id_mem_funct3),
        .is_branch    (id_is_branch),
        .is_jal       (id_is_jal),
        .is_jalr      (id_is_jalr),
        .illegal_inst (id_illegal_inst)
    );

    // Register file
    wire [31:0] id_rs1_data, id_rs2_data;

    // Writeback signals (from WB stage, defined below)
    wire        wb_reg_wr_en;
    wire [4:0]  wb_rd;
    wire [31:0] wb_rd_data;

    regfile u_regfile (
        .clk      (clk),
        .rst_n    (rst_n),
        .rs1_addr (id_rs1),
        .rs1_data (id_rs1_data),
        .rs2_addr (id_rs2),
        .rs2_data (id_rs2_data),
        .wr_en    (wb_reg_wr_en),
        .rd_addr  (wb_rd),
        .rd_data  (wb_rd_data)
    );

    // Immediate generation
    wire [31:0] id_imm;

    imm_gen u_imm_gen (
        .imm_type (id_imm_type),
        .inst     (if_id_inst),
        .imm      (id_imm)
    );

    // =====================================================================
    //  ID/EX Pipeline Register
    // =====================================================================
    reg [31:0] id_ex_pc;
    reg [31:0] id_ex_rs1_data;
    reg [31:0] id_ex_rs2_data;
    reg [31:0] id_ex_imm;
    reg [4:0]  id_ex_rs1;
    reg [4:0]  id_ex_rs2;
    reg [4:0]  id_ex_rd;
    reg [2:0]  id_ex_funct3;
    reg [3:0]  id_ex_alu_op;
    reg        id_ex_alu_src_b;
    reg        id_ex_reg_wr_en;
    reg [1:0]  id_ex_wb_sel;
    reg        id_ex_mem_rd_en;
    reg        id_ex_mem_wr_en;
    reg [2:0]  id_ex_mem_funct3;
    reg        id_ex_is_branch;
    reg        id_ex_is_jal;
    reg        id_ex_is_jalr;
    reg        id_ex_valid;
    // AUIPC flag: ALU src_a should be PC instead of rs1
    reg        id_ex_is_auipc;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || flush_ex || flush_id) begin
            id_ex_pc         <= 32'd0;
            id_ex_rs1_data   <= 32'd0;
            id_ex_rs2_data   <= 32'd0;
            id_ex_imm        <= 32'd0;
            id_ex_rs1        <= 5'd0;
            id_ex_rs2        <= 5'd0;
            id_ex_rd         <= 5'd0;
            id_ex_funct3     <= 3'd0;
            id_ex_alu_op     <= `ALU_ADD;
            id_ex_alu_src_b  <= 1'b0;
            id_ex_reg_wr_en  <= 1'b0;
            id_ex_wb_sel     <= 2'b00;
            id_ex_mem_rd_en  <= 1'b0;
            id_ex_mem_wr_en  <= 1'b0;
            id_ex_mem_funct3 <= 3'd0;
            id_ex_is_branch  <= 1'b0;
            id_ex_is_jal     <= 1'b0;
            id_ex_is_jalr    <= 1'b0;
            id_ex_valid      <= 1'b0;
            id_ex_is_auipc   <= 1'b0;
        end else if (!stall_id) begin
            id_ex_pc         <= if_id_pc;
            id_ex_rs1_data   <= id_rs1_data;
            id_ex_rs2_data   <= id_rs2_data;
            id_ex_imm        <= id_imm;
            id_ex_rs1        <= id_rs1;
            id_ex_rs2        <= id_rs2;
            id_ex_rd         <= id_rd;
            id_ex_funct3     <= id_funct3;
            id_ex_alu_op     <= id_alu_op;
            id_ex_alu_src_b  <= id_alu_src_b;
            id_ex_reg_wr_en  <= id_reg_wr_en;
            id_ex_wb_sel     <= id_wb_sel;
            id_ex_mem_rd_en  <= id_mem_rd_en;
            id_ex_mem_wr_en  <= id_mem_wr_en;
            id_ex_mem_funct3 <= id_mem_funct3;
            id_ex_is_branch  <= id_is_branch;
            id_ex_is_jal     <= id_is_jal;
            id_ex_is_jalr    <= id_is_jalr;
            id_ex_valid      <= if_id_valid;
            id_ex_is_auipc   <= (id_opcode == `OP_AUIPC);
        end
    end

    // =====================================================================
    //  STAGE 3: EXECUTE (EX)
    // =====================================================================

    // Forwarding muxes
    wire [31:0] ex_mem_alu_result;   // Forward from EX/MEM (defined below)
    wire [31:0] ex_fwd_rs1, ex_fwd_rs2;

    assign ex_fwd_rs1 = (fwd_a == `FWD_EX_MEM) ? ex_mem_alu_result :
                         (fwd_a == `FWD_MEM_WB) ? wb_rd_data :
                         id_ex_rs1_data;

    assign ex_fwd_rs2 = (fwd_b == `FWD_EX_MEM) ? ex_mem_alu_result :
                         (fwd_b == `FWD_MEM_WB) ? wb_rd_data :
                         id_ex_rs2_data;

    // ALU operand selection
    wire [31:0] alu_op_a = id_ex_is_auipc ? id_ex_pc : ex_fwd_rs1;
    wire [31:0] alu_op_b = id_ex_alu_src_b ? id_ex_imm : ex_fwd_rs2;

    // ALU
    wire [31:0] ex_alu_result;
    wire        ex_alu_zero;

    alu u_alu (
        .alu_op  (id_ex_alu_op),
        .op_a    (alu_op_a),
        .op_b    (alu_op_b),
        .result  (ex_alu_result),
        .zero    (ex_alu_zero)
    );

    // Branch evaluation
    wire ex_branch_cond;

    branch_unit u_branch (
        .funct3       (id_ex_funct3),
        .rs1_data     (ex_fwd_rs1),
        .rs2_data     (ex_fwd_rs2),
        .branch_taken (ex_branch_cond)
    );

    assign branch_taken_ex = id_ex_is_branch && ex_branch_cond && id_ex_valid;
    assign jump_taken_ex   = (id_ex_is_jal || id_ex_is_jalr) && id_ex_valid;

    // Branch/jump target calculation
    // JAL/Branch: PC + imm
    // JALR: (rs1 + imm) & ~1
    assign branch_target_ex = id_ex_is_jalr ?
                              (ex_fwd_rs1 + id_ex_imm) & 32'hFFFF_FFFE :
                              id_ex_pc + id_ex_imm;

    // =====================================================================
    //  EX/MEM Pipeline Register
    // =====================================================================
    reg [31:0] ex_mem_pc;
    reg [31:0] ex_mem_alu_result_reg;
    reg [31:0] ex_mem_rs2_data;
    reg [4:0]  ex_mem_rd;
    reg        ex_mem_reg_wr_en;
    reg [1:0]  ex_mem_wb_sel;
    reg        ex_mem_mem_rd_en;
    reg        ex_mem_mem_wr_en;
    reg [2:0]  ex_mem_mem_funct3;
    reg        ex_mem_valid;

    assign ex_mem_alu_result = ex_mem_alu_result_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ex_mem_pc             <= 32'd0;
            ex_mem_alu_result_reg <= 32'd0;
            ex_mem_rs2_data       <= 32'd0;
            ex_mem_rd             <= 5'd0;
            ex_mem_reg_wr_en      <= 1'b0;
            ex_mem_wb_sel         <= 2'b00;
            ex_mem_mem_rd_en      <= 1'b0;
            ex_mem_mem_wr_en      <= 1'b0;
            ex_mem_mem_funct3     <= 3'd0;
            ex_mem_valid          <= 1'b0;
        end else begin
            ex_mem_pc             <= id_ex_pc;
            ex_mem_alu_result_reg <= ex_alu_result;
            ex_mem_rs2_data       <= ex_fwd_rs2;
            ex_mem_rd             <= id_ex_rd;
            ex_mem_reg_wr_en      <= id_ex_reg_wr_en;
            ex_mem_wb_sel         <= id_ex_wb_sel;
            ex_mem_mem_rd_en      <= id_ex_mem_rd_en;
            ex_mem_mem_wr_en      <= id_ex_mem_wr_en;
            ex_mem_mem_funct3     <= id_ex_mem_funct3;
            ex_mem_valid          <= id_ex_valid;
        end
    end

    // =====================================================================
    //  STAGE 4: MEMORY ACCESS (MEM)
    // =====================================================================

    // Store data formatting
    wire [31:0] mem_store_data;
    wire [3:0]  mem_store_be;
    wire [31:0] mem_load_data;

    load_store_unit u_lsu (
        .funct3     (ex_mem_mem_funct3),
        .addr_lo    (ex_mem_alu_result_reg[1:0]),
        .mem_rdata  (dmem_rdata),
        .load_data  (mem_load_data),
        .rs2_data   (ex_mem_rs2_data),
        .store_data (mem_store_data),
        .store_be   (mem_store_be)
    );

    // Data memory interface
    assign dmem_addr  = {ex_mem_alu_result_reg[31:2], 2'b00}; // Word-aligned
    assign dmem_wdata = mem_store_data;
    assign dmem_rd    = ex_mem_mem_rd_en && ex_mem_valid;
    assign dmem_wr    = ex_mem_mem_wr_en && ex_mem_valid;
    assign dmem_be    = mem_store_be;

    // =====================================================================
    //  MEM/WB Pipeline Register
    // =====================================================================
    reg [31:0] mem_wb_pc;
    reg [31:0] mem_wb_alu_result;
    reg [31:0] mem_wb_load_data;
    reg [4:0]  mem_wb_rd_reg;
    reg        mem_wb_reg_wr_en_reg;
    reg [1:0]  mem_wb_wb_sel;
    reg        mem_wb_valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_wb_pc             <= 32'd0;
            mem_wb_alu_result     <= 32'd0;
            mem_wb_load_data      <= 32'd0;
            mem_wb_rd_reg         <= 5'd0;
            mem_wb_reg_wr_en_reg  <= 1'b0;
            mem_wb_wb_sel         <= 2'b00;
            mem_wb_valid          <= 1'b0;
        end else begin
            mem_wb_pc             <= ex_mem_pc;
            mem_wb_alu_result     <= ex_mem_alu_result_reg;
            mem_wb_load_data      <= mem_load_data;
            mem_wb_rd_reg         <= ex_mem_rd;
            mem_wb_reg_wr_en_reg  <= ex_mem_reg_wr_en;
            mem_wb_wb_sel         <= ex_mem_wb_sel;
            mem_wb_valid          <= ex_mem_valid;
        end
    end

    // =====================================================================
    //  STAGE 5: WRITEBACK (WB)
    // =====================================================================
    assign wb_rd = mem_wb_rd_reg;
    assign wb_reg_wr_en = mem_wb_reg_wr_en_reg && mem_wb_valid;

    assign wb_rd_data = (mem_wb_wb_sel == 2'b00) ? mem_wb_alu_result :
                        (mem_wb_wb_sel == 2'b01) ? mem_wb_load_data :
                        (mem_wb_wb_sel == 2'b10) ? mem_wb_pc + 32'd4 :
                        32'd0;

    // =====================================================================
    //  Hazard Unit
    // =====================================================================
    hazard_unit u_hazard (
        // EX stage source registers (for forwarding)
        .id_ex_rs1         (id_ex_rs1),
        .id_ex_rs2         (id_ex_rs2),

        // EX/MEM destination (for forwarding)
        .ex_mem_rd         (ex_mem_rd),
        .ex_mem_reg_wr_en  (ex_mem_reg_wr_en && ex_mem_valid),
        .ex_mem_mem_rd_en  (ex_mem_mem_rd_en),

        // MEM/WB destination (for forwarding)
        .mem_wb_rd         (mem_wb_rd_reg),
        .mem_wb_reg_wr_en  (mem_wb_reg_wr_en_reg && mem_wb_valid),

        // IF/ID source registers (for load-use detection)
        .if_id_rs1         (id_rs1),
        .if_id_rs2         (id_rs2),

        // ID/EX destination (for load-use detection)
        .id_ex_rd          (id_ex_rd),
        .id_ex_mem_rd_en   (id_ex_mem_rd_en),

        // Branch/jump
        .branch_taken      (branch_taken_ex),
        .jump_taken        (jump_taken_ex),

        // Outputs
        .fwd_a             (fwd_a),
        .fwd_b             (fwd_b),
        .stall_if          (stall_if),
        .stall_id          (stall_id),
        .flush_id          (flush_id),
        .flush_ex          (flush_ex)
    );

endmodule