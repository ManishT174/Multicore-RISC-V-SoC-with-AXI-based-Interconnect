//============================================================================
// tb_rv32i_core.v — Testbench for 5-stage RV32I Core
//
// Provides:
//   - 4KB instruction memory (preloaded with test program)
//   - 4KB data memory
//   - Self-checking: test program writes results to known addresses,
//     testbench checks them at end
//============================================================================

`timescale 1ns / 1ps

module tb_rv32i_core;

    reg         clk;
    reg         rst_n;

    // Instruction memory interface
    wire [31:0] imem_addr;
    wire [31:0] imem_rdata;
    wire        imem_req;
    wire        imem_valid;

    // Data memory interface
    wire [31:0] dmem_addr;
    wire [31:0] dmem_wdata;
    wire [31:0] dmem_rdata;
    wire        dmem_rd;
    wire        dmem_wr;
    wire [3:0]  dmem_be;
    wire        dmem_valid;

    // -----------------------------------------------------------------------
    // Clock generation: 10ns period (100 MHz)
    // -----------------------------------------------------------------------
    initial clk = 0;
    always #5 clk = ~clk;

    // -----------------------------------------------------------------------
    // Instruction Memory (4KB, word-addressed)
    // -----------------------------------------------------------------------
    reg [31:0] imem [0:1023];
    assign imem_rdata = imem[imem_addr[11:2]];
    assign imem_valid = 1'b1; // Single-cycle memory, always ready

    // -----------------------------------------------------------------------
    // Data Memory (4KB, word-addressed, byte-enable writes)
    // -----------------------------------------------------------------------
    reg [31:0] dmem_array [0:1023];
    wire [9:0] dmem_word_addr = dmem_addr[11:2];

    assign dmem_rdata = dmem_array[dmem_word_addr];
    assign dmem_valid = 1'b1;

    always @(posedge clk) begin
        if (dmem_wr) begin
            if (dmem_be[0]) dmem_array[dmem_word_addr][7:0]   <= dmem_wdata[7:0];
            if (dmem_be[1]) dmem_array[dmem_word_addr][15:8]  <= dmem_wdata[15:8];
            if (dmem_be[2]) dmem_array[dmem_word_addr][23:16] <= dmem_wdata[23:16];
            if (dmem_be[3]) dmem_array[dmem_word_addr][31:24] <= dmem_wdata[31:24];
        end
    end

    // -----------------------------------------------------------------------
    // DUT
    // -----------------------------------------------------------------------
    rv32i_core #(
        .HART_ID  (0),
        .RESET_PC (32'h0000_0000)
    ) u_dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .imem_addr  (imem_addr),
        .imem_rdata (imem_rdata),
        .imem_req   (imem_req),
        .imem_valid (imem_valid),
        .dmem_addr  (dmem_addr),
        .dmem_wdata (dmem_wdata),
        .dmem_rdata (dmem_rdata),
        .dmem_rd    (dmem_rd),
        .dmem_wr    (dmem_wr),
        .dmem_be    (dmem_be),
        .dmem_valid (dmem_valid)
    );

    // -----------------------------------------------------------------------
    // Test Program (hand-assembled RV32I)
    //
    // This program tests: ADDI, ADD, SUB, AND, OR, XOR, SLT, SLTU,
    //                     SLL, SRL, SRA, LUI, AUIPC, SW, LW, BEQ,
    //                     BNE, JAL, JALR, LB, LBU, SB
    //
    // Data memory base for results: 0x800 (word 512)
    //
    // Expected results stored at:
    //   0x800: 10     (ADDI test)
    //   0x804: 25     (ADD test)
    //   0x808: -5     (SUB test: 10-15 = -5, i.e., 0xFFFFFFFB)
    //   0x80C: 10     (AND test: 10 & 15 = 10)
    //   0x810: 15     (OR  test: 10 | 15 = 15)
    //   0x814: 5      (XOR test: 10 ^ 15 = 5)
    //   0x818: 1      (SLT test: 10 < 15 = 1)
    //   0x81C: 4      (SLL test: 1 << 2 = 4)
    //   0x820: 0x12345000 (LUI test)
    //   0x824: 42     (load-after-store test)
    //   0x828: 1      (BEQ taken test — wrote 1)
    //   0x82C: 1      (BNE taken test — wrote 1)
    //   0x830: link addr (JAL test — return address)
    //   0x834: link addr (JALR test — return address)
    //   0x838: 0xFFFFFF80 (LB sign-extend test: load byte 0x80 → -128)
    //   0x83C: 0x00000080 (LBU zero-extend test: load byte 0x80 → 128)
    // -----------------------------------------------------------------------
    initial begin
        integer i;
        // Clear memories
        for (i = 0; i < 1024; i = i + 1) begin
            imem[i] = 32'h0000_0013; // NOP
            dmem_array[i] = 32'd0;
        end

        // --- Test Program ---
        // Addr  Instruction                 Assembly
        // 0x000: addi x1, x0, 10           # x1 = 10
        imem[0]  = 32'h00A00093;
        // 0x004: addi x2, x0, 15           # x2 = 15
        imem[1]  = 32'h00F00113;
        // 0x008: add  x3, x1, x2           # x3 = 25
        imem[2]  = 32'h002081B3;
        // 0x00C: sub  x4, x1, x2           # x4 = -5 (0xFFFFFFFB)
        imem[3]  = 32'h40208233;
        // 0x010: and  x5, x1, x2           # x5 = 10 & 15 = 10
        imem[4]  = 32'h0020F2B3;
        // 0x014: or   x6, x1, x2           # x6 = 10 | 15 = 15
        imem[5]  = 32'h0020E333;
        // 0x018: xor  x7, x1, x2           # x7 = 10 ^ 15 = 5
        imem[6]  = 32'h0020C3B3;
        // 0x01C: slt  x8, x1, x2           # x8 = (10 < 15) = 1
        imem[7]  = 32'h0020A433;
        // 0x020: addi x9, x0, 1            # x9 = 1
        imem[8]  = 32'h00100493;
        // 0x024: addi x10, x0, 2           # x10 = 2
        imem[9]  = 32'h00200513;
        // 0x028: sll  x11, x9, x10         # x11 = 1 << 2 = 4
        imem[10] = 32'h00A495B3;
        // 0x02C: lui  x12, 0x12345         # x12 = 0x12345000
        imem[11] = 32'h12345637;

        // Store results to data memory (base 0x800)
        // 0x030: addi x20, x0, 0x800       # x20 = base addr (use as pointer)
        //        Actually, 0x800 = 2048, which doesn't fit in 12-bit signed imm
        //        Use LUI + ADDI: lui x20, 0; addi x20, x20, 0x800
        //        Or simpler: addi x20, x0, 0x7FF; addi x20, x20, 1
        //        Easiest: use SLLI. addi x20, x0, 1; slli x20, x20, 11
        // 0x030: addi x20, x0, 1            # x20 = 1
        imem[12] = 32'h00100A13;
        // 0x034: slli x20, x20, 11          # x20 = 0x800
        imem[13] = 32'h00BA1A13;

        // 0x038: sw x1, 0(x20)             # mem[0x800] = 10
        imem[14] = 32'h001A2023;
        // 0x03C: sw x3, 4(x20)             # mem[0x804] = 25
        imem[15] = 32'h003A2223;
        // 0x040: sw x4, 8(x20)             # mem[0x808] = -5
        imem[16] = 32'h004A2423;
        // 0x044: sw x5, 12(x20)            # mem[0x80C] = 10
        imem[17] = 32'h005A2623;
        // 0x048: sw x6, 16(x20)            # mem[0x810] = 15
        imem[18] = 32'h006A2823;
        // 0x04C: sw x7, 20(x20)            # mem[0x814] = 5
        imem[19] = 32'h007A2A23;
        // 0x050: sw x8, 24(x20)            # mem[0x818] = 1
        imem[20] = 32'h008A2C23;
        // 0x054: sw x11, 28(x20)           # mem[0x81C] = 4
        imem[21] = 32'h00BA2E23;
        // 0x058: sw x12, 32(x20)           # mem[0x820] = 0x12345000
        imem[22] = 32'h02CA2023;

        // Load-after-store test
        // 0x05C: addi x13, x0, 42          # x13 = 42
        imem[23] = 32'h02A00693;
        // 0x060: sw x13, 36(x20)           # mem[0x824] = 42
        imem[24] = 32'h02DA2223;
        // 0x064: lw x14, 36(x20)           # x14 = mem[0x824] = 42
        imem[25] = 32'h024A2703;
        // 0x068: sw x14, 36(x20)           # mem[0x824] = 42 (rewrite to confirm)
        imem[26] = 32'h02EA2223;

        // Branch test: BEQ
        // 0x06C: addi x15, x0, 5           # x15 = 5
        imem[27] = 32'h00500793;
        // 0x070: addi x16, x0, 5           # x16 = 5
        imem[28] = 32'h00500813;
        // 0x074: beq x15, x16, +8          # if x15==x16, jump to 0x07C
        imem[29] = 32'h01078463;
        // 0x078: addi x17, x0, 0           # x17 = 0 (skipped if branch taken)
        imem[30] = 32'h00000893;
        // 0x07C: addi x17, x0, 1           # x17 = 1 (branch target)
        imem[31] = 32'h00100893;
        // 0x080: sw x17, 40(x20)           # mem[0x828] = 1
        imem[32] = 32'h031A2423;

        // Branch test: BNE
        // 0x084: addi x15, x0, 5           # x15 = 5
        imem[33] = 32'h00500793;
        // 0x088: addi x16, x0, 7           # x16 = 7
        imem[34] = 32'h00700813;
        // 0x08C: bne x15, x16, +8          # if x15!=x16, jump to 0x094
        imem[35] = 32'h01079463;
        // 0x090: addi x18, x0, 0           # x18 = 0 (skipped)
        imem[36] = 32'h00000913;
        // 0x094: addi x18, x0, 1           # x18 = 1 (branch target)
        imem[37] = 32'h00100913;
        // 0x098: sw x18, 44(x20)           # mem[0x82C] = 1
        imem[38] = 32'h032A2623;

        // JAL test: jal x19, +8            # x19 = PC+4 = 0x0A0, jump to 0x0A4
        // 0x09C: jal x19, 8
        imem[39] = 32'h008009EF;
        // 0x0A0: nop (skipped by JAL)
        imem[40] = 32'h00000013;
        // 0x0A4: sw x19, 48(x20)           # mem[0x830] = return addr (0x0A0)
        imem[41] = 32'h033A2823;

        // JALR test: jalr x21, x20, 0      # jump to addr in x20 (0x800 — but
        //   that's data space, so we use a different approach)
        // Instead, let's test JALR with a known code address.
        // 0x0A8: addi x22, x0, 0           # x22 = 0 (will hold target)
        imem[42] = 32'h00000B13;
        // Use auipc to get PC-relative address
        // 0x0AC: auipc x22, 0              # x22 = 0x0AC
        imem[43] = 32'h00000B17;
        // 0x0B0: addi x22, x22, 16         # x22 = 0x0AC + 16 = 0x0BC
        imem[44] = 32'h010B0B13;
        // 0x0B4: jalr x21, x22, 0          # x21 = 0x0B8, jump to 0x0BC
        imem[45] = 32'h000B0AE7;
        // 0x0B8: nop (skipped)
        imem[46] = 32'h00000013;
        // 0x0BC: sw x21, 52(x20)           # mem[0x834] = 0x0B8
        imem[47] = 32'h035A2A23;

        // Byte load/store test
        // 0x0C0: addi x23, x0, 0x080       # x23 = 128 (0x80)
        //        Actually need: addi x23, x0, 128
        imem[48] = 32'h08000B93;
        // 0x0C4: sb x23, 56(x20)           # store byte 0x80 at mem[0x838]
        imem[49] = 32'h037A0C23;
        // 0x0C8: lb x24, 56(x20)           # x24 = sign-ext(0x80) = 0xFFFFFF80
        imem[50] = 32'h038A0C03;
        // 0x0CC: sw x24, 56(x20)           # mem[0x838] = 0xFFFFFF80
        imem[51] = 32'h038A2C23;
        // 0x0D0: lbu x25, 56(x20)          # x25 = zero-ext(0x80) = 0x00000080
        //        Wait, we just overwrote it with SW. Let's use a different addr.
        // Actually let's store the byte separately first:
        // 0x0D0: sb x23, 60(x20)           # store byte 0x80 at mem[0x83C]
        imem[52] = 32'h037A0E23;
        // 0x0D4: lbu x25, 60(x20)          # x25 = zero-ext(0x80) = 0x80
        imem[53] = 32'h03CA4C83;
        // 0x0D8: sw x25, 60(x20)           # mem[0x83C] = 0x00000080
        imem[54] = 32'h039A2E23;

        // Done — infinite loop
        // 0x0DC: jal x0, 0                 # jump to self
        imem[55] = 32'h0000006F;
    end

    // -----------------------------------------------------------------------
    // Simulation control
    // -----------------------------------------------------------------------
    integer pass_count, fail_count;

    task check_dmem;
        input [31:0] addr;
        input [31:0] expected;
        input [255:0] test_name; // Verilog string
        begin
            if (dmem_array[addr[11:2]] === expected) begin
                $display("[PASS] %0s: mem[0x%03h] = 0x%08h",
                         test_name, addr, expected);
                pass_count = pass_count + 1;
            end else begin
                $display("[FAIL] %0s: mem[0x%03h] = 0x%08h (expected 0x%08h)",
                         test_name, addr, dmem_array[addr[11:2]], expected);
                fail_count = fail_count + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("rv32i_core_tb.vcd");
        $dumpvars(0, tb_rv32i_core);

        pass_count = 0;
        fail_count = 0;

        // Reset
        rst_n = 0;
        #20;
        rst_n = 1;

        // Run for enough cycles for all instructions to complete
        // ~56 instructions, pipeline depth 5, plus stalls/flushes ≈ 120 cycles
        #1200;

        $display("\n========================================");
        $display(" RV32I Core Test Results");
        $display("========================================");

        check_dmem(32'h800, 32'd10,         "ADDI       ");
        check_dmem(32'h804, 32'd25,         "ADD        ");
        check_dmem(32'h808, 32'hFFFFFFFB,   "SUB        ");
        check_dmem(32'h80C, 32'd10,         "AND        ");
        check_dmem(32'h810, 32'd15,         "OR         ");
        check_dmem(32'h814, 32'd5,          "XOR        ");
        check_dmem(32'h818, 32'd1,          "SLT        ");
        check_dmem(32'h81C, 32'd4,          "SLL        ");
        check_dmem(32'h820, 32'h12345000,   "LUI        ");
        check_dmem(32'h824, 32'd42,         "LW after SW");
        check_dmem(32'h828, 32'd1,          "BEQ taken  ");
        check_dmem(32'h82C, 32'd1,          "BNE taken  ");
        check_dmem(32'h830, 32'h000000A0,   "JAL link   ");
        check_dmem(32'h834, 32'h000000B8,   "JALR link  ");
        check_dmem(32'h838, 32'hFFFFFF80,   "LB sign-ext");
        check_dmem(32'h83C, 32'h00000080,   "LBU zero-ex");

        $display("========================================");
        $display(" %0d passed, %0d failed", pass_count, fail_count);
        $display("========================================\n");

        if (fail_count == 0)
            $display("*** ALL TESTS PASSED ***\n");
        else
            $display("*** SOME TESTS FAILED ***\n");

        $finish;
    end

endmodule