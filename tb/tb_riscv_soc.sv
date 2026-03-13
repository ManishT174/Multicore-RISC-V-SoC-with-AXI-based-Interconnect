//============================================================================
// tb_riscv_soc.sv — SoC Integration Testbench
//============================================================================

`timescale 1ns / 1ps

module tb_riscv_soc;

    logic clk, rst_n;
    logic uart_tx, uart_rx;
    logic irq_timer, irq_uart_tx;

    initial clk = 0;
    always #5 clk = ~clk;
    assign uart_rx = 1'b1;

    riscv_soc_top #(
        .HART_ID   (0),
        .NUM_HARTS (4)
    ) u_dut (
        .clk(clk), .rst_n(rst_n), .uart_tx(uart_tx), .uart_rx(uart_rx),
        .irq_timer(irq_timer), .irq_uart_tx(irq_uart_tx)
    );

    // Load test program (Python-verified encodings)
    initial begin
        u_dut.u_boot_rom.mem[0]  = 32'h800000B7;  // lui x1, 0x80000
        u_dut.u_boot_rom.mem[1]  = 32'hCAFEC137;  // lui x2, 0xCAFEC
        u_dut.u_boot_rom.mem[2]  = 32'hABE10113;  // addi x2, x2, -1346
        u_dut.u_boot_rom.mem[3]  = 32'h0020A023;  // sw x2, 0(x1)
        u_dut.u_boot_rom.mem[4]  = 32'h0000A183;  // lw x3, 0(x1)
        u_dut.u_boot_rom.mem[5]  = 32'h0030A023;  // sw x3, 0(x1)
        u_dut.u_boot_rom.mem[6]  = 32'hF0020237;  // lui x4, 0xF0020
        u_dut.u_boot_rom.mem[7]  = 32'h00022283;  // lw x5, 0(x4)   HART_ID
        u_dut.u_boot_rom.mem[8]  = 32'h0050A223;  // sw x5, 4(x1)
        u_dut.u_boot_rom.mem[9]  = 32'h00422303;  // lw x6, 4(x4)   NUM_HARTS
        u_dut.u_boot_rom.mem[10] = 32'h0060A423;  // sw x6, 8(x1)
        u_dut.u_boot_rom.mem[11] = 32'hF00103B7;  // lui x7, 0xF0010
        u_dut.u_boot_rom.mem[12] = 32'h00100413;  // addi x8, x0, 1
        u_dut.u_boot_rom.mem[13] = 32'h0083A823;  // sw x8, 0x10(x7) enable timer
        u_dut.u_boot_rom.mem[14] = 32'h00000013;  // nop
        u_dut.u_boot_rom.mem[15] = 32'h00000013;  // nop
        u_dut.u_boot_rom.mem[16] = 32'h00000013;  // nop
        u_dut.u_boot_rom.mem[17] = 32'h00000013;  // nop
        u_dut.u_boot_rom.mem[18] = 32'h00000013;  // nop
        u_dut.u_boot_rom.mem[19] = 32'h0003A483;  // lw x9, 0(x7)   mtime_lo
        u_dut.u_boot_rom.mem[20] = 32'h0090A623;  // sw x9, 12(x1)
        u_dut.u_boot_rom.mem[21] = 32'hF0000537;  // lui x10, 0xF0000
        u_dut.u_boot_rom.mem[22] = 32'h04800593;  // addi x11, x0, 'H'
        u_dut.u_boot_rom.mem[23] = 32'h00B52023;  // sw x11, 0(x10)  UART TX
        u_dut.u_boot_rom.mem[24] = 32'h0000006F;  // jal x0, 0 (loop)
    end

    integer pass_count, fail_count;

    task automatic check_ram(input int offset, input logic [31:0] expected,
                             input string name);
        logic [31:0] actual;
        int word_idx = offset / 4;
        actual = {u_dut.u_main_ram.mem_b3[word_idx],
                  u_dut.u_main_ram.mem_b2[word_idx],
                  u_dut.u_main_ram.mem_b1[word_idx],
                  u_dut.u_main_ram.mem_b0[word_idx]};
        if (actual === expected) begin
            $display("[PASS] %s: RAM[0x%04h] = 0x%08h", name, offset, actual);
            pass_count++;
        end else begin
            $display("[FAIL] %s: RAM[0x%04h] = 0x%08h (expected 0x%08h)",
                     name, offset, actual, expected);
            fail_count++;
        end
    endtask

    task automatic check_ram_nonzero(input int offset, input string name);
        logic [31:0] actual;
        int word_idx = offset / 4;
        actual = {u_dut.u_main_ram.mem_b3[word_idx],
                  u_dut.u_main_ram.mem_b2[word_idx],
                  u_dut.u_main_ram.mem_b1[word_idx],
                  u_dut.u_main_ram.mem_b0[word_idx]};
        if (actual !== 32'd0) begin
            $display("[PASS] %s: RAM[0x%04h] = 0x%08h (nonzero)", name, offset, actual);
            pass_count++;
        end else begin
            $display("[FAIL] %s: RAM[0x%04h] = 0x%08h (expected nonzero)",
                     name, offset, actual);
            fail_count++;
        end
    endtask

    initial begin
        $dumpfile("riscv_soc_tb.vcd");
        $dumpvars(0, tb_riscv_soc);
        pass_count = 0;
        fail_count = 0;

        rst_n = 0;
        #50;
        rst_n = 1;
        #3000;

        $display("");
        $display("========================================");
        $display(" SoC Integration Test Results");
        $display("========================================");

        check_ram(0,  32'hCAFEBABE, "RAM write/readback ");
        check_ram(4,  32'd0,        "SYSCTRL HART_ID    ");
        check_ram(8,  32'd4,        "SYSCTRL NUM_HARTS  ");
        check_ram_nonzero(12,       "Timer mtime nonzero");

        $display("========================================");
        $display(" %0d passed, %0d failed", pass_count, fail_count);
        $display("========================================");
        if (fail_count == 0)
            $display("\n*** ALL SOC TESTS PASSED ***\n");
        else
            $display("\n*** SOME TESTS FAILED ***\n");
        $finish;
    end

endmodule