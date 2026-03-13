//============================================================================
// tb_multicore_noc.sv — 4-Core NoC Integration Testbench
//
// Test program (same code runs on all 4 cores):
//   1. Each core determines its hart ID by reading a unique value.
//      Since SYSCTRL returns hart 0 for all, we use a different
//      mechanism: each core atomically increments a shared counter
//      at RAM[0x100] to claim a unique ID.
//
//   Simplified approach (no atomics needed):
//   - Core N is instantiated with HART_ID = N
//   - The test program uses AUIPC to derive a core-unique value
//     (all cores start at same PC, but we encode HART_ID in the core)
//   - Actually simplest: each core writes a signature value
//     (HART_ID * 0x1111_1111) to RAM[HART_ID * 4]
//   - Then each core polls RAM[0x10] until it reads 0xDONE
//   - Core 0 sets that flag after checking all signatures
//
//   Even simpler for verification: each core writes a unique pattern
//   to a unique address, we check in the testbench.
//
// What this tests:
//   - All 4 cores boot and execute independently
//   - All 4 cores can write to shared RAM through the AXI NoC
//   - Crossbar correctly arbitrates competing writes
//   - Data integrity: each core's write is visible to the testbench
//============================================================================

`timescale 1ns / 1ps

module tb_multicore_noc;

    logic clk, rst_n;
    logic uart_tx, uart_rx;
    logic irq_timer, irq_uart_tx;

    initial clk = 0;
    always #5 clk = ~clk;
    assign uart_rx = 1'b1;

    // -----------------------------------------------------------------------
    // DUT
    // -----------------------------------------------------------------------
    multicore_noc_top #(
        .NUM_CORES (4)
    ) u_dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .uart_tx     (uart_tx),
        .uart_rx     (uart_rx),
        .irq_timer   (irq_timer),
        .irq_uart_tx (irq_uart_tx)
    );

    // -----------------------------------------------------------------------
    // Test program
    //
    // Each core executes the same code. The core's HART_ID parameter
    // uniquely identifies it. We use a trick: the code reads from
    // SYSCTRL (which returns 0 for all), but since we need per-core
    // differentiation, we use the HART_ID CSR concept.
    //
    // Actually, our core doesn't have CSR support. But the core's
    // HART_ID is baked in. The simplest approach for testing:
    // Each core writes value (0xC0RE_0000 | hart_id) to
    // RAM[hart_id * 4].
    //
    // Problem: the code is the same for all cores, so how does each
    // core know its ID? Answer: we have SYSCTRL, but it returns 0
    // for all. Let's fix this in the test by giving each core a
    // slightly different program that knows its own ID.
    //
    // Most practical: use the AUIPC + self-detection trick, OR
    // just load different programs into each core's private iROM.
    // Since each core has its own boot_rom instance (gen_cores[ci].u_irom),
    // we can load different code per core.
    // -----------------------------------------------------------------------

    // Python-verified machine code generator (from earlier)
    // Core program template:
    //   lui  x1, 0x80000       # x1 = RAM base 0x80000000
    //   addi x2, x0, HART_ID  # x2 = this core's ID
    //   slli x3, x2, 2         # x3 = HART_ID * 4 (byte offset)
    //   add  x4, x1, x3        # x4 = &RAM[HART_ID]
    //   lui  x5, 0xC0RE0       # x5 = 0xC0RE0000 (signature base)
    //   or   x5, x5, x2        # x5 = 0xC0RE0000 | HART_ID
    //   sw   x5, 0(x4)         # RAM[HART_ID*4] = signature
    //   jal  x0, 0             # infinite loop

    function automatic [31:0] encode_lui(input [4:0] rd, input [19:0] imm20);
        return {imm20, rd, 7'b0110111};
    endfunction

    function automatic [31:0] encode_addi(input [4:0] rd, input [4:0] rs1, input [11:0] imm12);
        return {imm12, rs1, 3'b000, rd, 7'b0010011};
    endfunction

    function automatic [31:0] encode_slli(input [4:0] rd, input [4:0] rs1, input [4:0] shamt);
        return {7'b0000000, shamt, rs1, 3'b001, rd, 7'b0010011};
    endfunction

    function automatic [31:0] encode_add(input [4:0] rd, input [4:0] rs1, input [4:0] rs2);
        return {7'b0000000, rs2, rs1, 3'b000, rd, 7'b0110011};
    endfunction

    function automatic [31:0] encode_or(input [4:0] rd, input [4:0] rs1, input [4:0] rs2);
        return {7'b0000000, rs2, rs1, 3'b110, rd, 7'b0110011};
    endfunction

    function automatic [31:0] encode_sw(input [4:0] rs2, input [4:0] rs1, input [11:0] imm12);
        return {imm12[11:5], rs2, rs1, 3'b010, imm12[4:0], 7'b0100011};
    endfunction

    function automatic [31:0] encode_lw(input [4:0] rd, input [4:0] rs1, input [11:0] imm12);
        return {imm12, rs1, 3'b010, rd, 7'b0000011};
    endfunction

    // Load per-core programs
    initial begin
        for (int ci = 0; ci < 4; ci++) begin
            // Clear ROM
            for (int i = 0; i < 4096; i++) begin
                case (ci)
                    0: u_dut.gen_cores[0].u_irom.mem[i] = 32'h0000_0013;
                    1: u_dut.gen_cores[1].u_irom.mem[i] = 32'h0000_0013;
                    2: u_dut.gen_cores[2].u_irom.mem[i] = 32'h0000_0013;
                    3: u_dut.gen_cores[3].u_irom.mem[i] = 32'h0000_0013;
                endcase
            end
        end

        // ---- Core 0 program ----
        u_dut.gen_cores[0].u_irom.mem[0] = encode_lui(1, 20'h80000);       // x1 = 0x80000000
        u_dut.gen_cores[0].u_irom.mem[1] = encode_addi(2, 0, 12'd0);      // x2 = 0 (HART_ID)
        u_dut.gen_cores[0].u_irom.mem[2] = encode_slli(3, 2, 5'd2);       // x3 = 0
        u_dut.gen_cores[0].u_irom.mem[3] = encode_add(4, 1, 3);           // x4 = 0x80000000
        u_dut.gen_cores[0].u_irom.mem[4] = encode_lui(5, 20'hC0E00);      // x5 = 0xC0E00000
        u_dut.gen_cores[0].u_irom.mem[5] = encode_or(5, 5, 2);            // x5 = 0xC0E00000
        u_dut.gen_cores[0].u_irom.mem[6] = encode_sw(5, 4, 12'd0);        // RAM[0] = 0xC0E00000
        u_dut.gen_cores[0].u_irom.mem[7] = 32'h0000_006F;                 // jal x0, 0

        // ---- Core 1 program ----
        u_dut.gen_cores[1].u_irom.mem[0] = encode_lui(1, 20'h80000);
        u_dut.gen_cores[1].u_irom.mem[1] = encode_addi(2, 0, 12'd1);      // x2 = 1
        u_dut.gen_cores[1].u_irom.mem[2] = encode_slli(3, 2, 5'd2);       // x3 = 4
        u_dut.gen_cores[1].u_irom.mem[3] = encode_add(4, 1, 3);           // x4 = 0x80000004
        u_dut.gen_cores[1].u_irom.mem[4] = encode_lui(5, 20'hC0E00);
        u_dut.gen_cores[1].u_irom.mem[5] = encode_or(5, 5, 2);            // x5 = 0xC0E00001
        u_dut.gen_cores[1].u_irom.mem[6] = encode_sw(5, 4, 12'd0);
        u_dut.gen_cores[1].u_irom.mem[7] = 32'h0000_006F;

        // ---- Core 2 program ----
        u_dut.gen_cores[2].u_irom.mem[0] = encode_lui(1, 20'h80000);
        u_dut.gen_cores[2].u_irom.mem[1] = encode_addi(2, 0, 12'd2);      // x2 = 2
        u_dut.gen_cores[2].u_irom.mem[2] = encode_slli(3, 2, 5'd2);       // x3 = 8
        u_dut.gen_cores[2].u_irom.mem[3] = encode_add(4, 1, 3);           // x4 = 0x80000008
        u_dut.gen_cores[2].u_irom.mem[4] = encode_lui(5, 20'hC0E00);
        u_dut.gen_cores[2].u_irom.mem[5] = encode_or(5, 5, 2);            // x5 = 0xC0E00002
        u_dut.gen_cores[2].u_irom.mem[6] = encode_sw(5, 4, 12'd0);
        u_dut.gen_cores[2].u_irom.mem[7] = 32'h0000_006F;

        // ---- Core 3 program ----
        u_dut.gen_cores[3].u_irom.mem[0] = encode_lui(1, 20'h80000);
        u_dut.gen_cores[3].u_irom.mem[1] = encode_addi(2, 0, 12'd3);      // x2 = 3
        u_dut.gen_cores[3].u_irom.mem[2] = encode_slli(3, 2, 5'd2);       // x3 = 12
        u_dut.gen_cores[3].u_irom.mem[3] = encode_add(4, 1, 3);           // x4 = 0x8000000C
        u_dut.gen_cores[3].u_irom.mem[4] = encode_lui(5, 20'hC0E00);
        u_dut.gen_cores[3].u_irom.mem[5] = encode_or(5, 5, 2);            // x5 = 0xC0E00003
        u_dut.gen_cores[3].u_irom.mem[6] = encode_sw(5, 4, 12'd0);
        u_dut.gen_cores[3].u_irom.mem[7] = 32'h0000_006F;
    end

    // -----------------------------------------------------------------------
    // Check results
    // -----------------------------------------------------------------------
    integer pass_count, fail_count;

    task automatic check_ram(input int word_idx, input logic [31:0] expected,
                             input string name);
        logic [31:0] actual;
        actual = {u_dut.u_main_ram.mem_b3[word_idx],
                  u_dut.u_main_ram.mem_b2[word_idx],
                  u_dut.u_main_ram.mem_b1[word_idx],
                  u_dut.u_main_ram.mem_b0[word_idx]};
        if (actual === expected) begin
            $display("[PASS] %s: RAM[%0d] = 0x%08h", name, word_idx, actual);
            pass_count++;
        end else begin
            $display("[FAIL] %s: RAM[%0d] = 0x%08h (expected 0x%08h)",
                     name, word_idx, actual, expected);
            fail_count++;
        end
    endtask

    initial begin
        $dumpfile("multicore_noc_tb.vcd");
        $dumpvars(0, tb_multicore_noc);

        pass_count = 0;
        fail_count = 0;

        rst_n = 0;
        #100;
        rst_n = 1;

        // Each core needs ~8 instructions × pipeline + AXI bridge latency
        // With 4 cores contending for RAM: ~8 inst + ~5 cycle AXI per write
        // + arbitration delays. 500 cycles should be more than enough.
        #5000;

        $display("");
        $display("========================================");
        $display(" 4-Core NoC Integration Test Results");
        $display("========================================");

        check_ram(0, 32'hC0E0_0000, "Core 0 signature");
        check_ram(1, 32'hC0E0_0001, "Core 1 signature");
        check_ram(2, 32'hC0E0_0002, "Core 2 signature");
        check_ram(3, 32'hC0E0_0003, "Core 3 signature");

        $display("========================================");
        $display(" %0d passed, %0d failed", pass_count, fail_count);
        $display("========================================");

        if (fail_count == 0)
            $display("\n*** ALL 4-CORE NOC TESTS PASSED ***\n");
        else
            $display("\n*** SOME TESTS FAILED ***\n");

        $finish;
    end

endmodule