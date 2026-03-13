//============================================================================
// addr_decoder.sv — Address Decoder
//
// Maps a 32-bit address to a slave ID and local offset.
// Returns SLAVE_NONE on decode error (unmapped region).
//============================================================================

module addr_decoder
    import soc_pkg::*;
(
    input  logic [31:0]  addr,
    output slave_id_t    slave_sel,
    output logic [31:0]  local_addr,
    output logic         decode_error
);

    always_comb begin
        // Defaults
        slave_sel    = SLAVE_NONE;
        local_addr   = '0;
        decode_error = 1'b0;

        // Priority-encoded address match
        // ROM: 0x0000_0000 — 0x0000_3FFF
        if (addr >= ROM_BASE && addr < (ROM_BASE + ROM_SIZE)) begin
            slave_sel  = SLAVE_ROM;
            local_addr = {20'b0, addr[13:0]}; // 14-bit offset for 16KB
        end
        // RAM: 0x8000_0000 — 0x8000_FFFF
        else if (addr >= RAM_BASE && addr < (RAM_BASE + RAM_SIZE)) begin
            slave_sel  = SLAVE_RAM;
            local_addr = {16'b0, addr[15:0]}; // 16-bit offset for 64KB
        end
        // UART: 0xF000_0000 — 0xF000_0FFF
        else if (addr >= UART_BASE && addr < (UART_BASE + UART_SIZE)) begin
            slave_sel  = SLAVE_UART;
            local_addr = {20'b0, addr[11:0]};
        end
        // Timer: 0xF001_0000 — 0xF001_0FFF
        else if (addr >= TIMER_BASE && addr < (TIMER_BASE + TIMER_SIZE)) begin
            slave_sel  = SLAVE_TIMER;
            local_addr = {20'b0, addr[11:0]};
        end
        // System Control: 0xF002_0000 — 0xF002_0FFF
        else if (addr >= SYSCTRL_BASE && addr < (SYSCTRL_BASE + SYSCTRL_SIZE)) begin
            slave_sel  = SLAVE_SYSCTRL;
            local_addr = {20'b0, addr[11:0]};
        end
        // Unmapped
        else begin
            slave_sel    = SLAVE_NONE;
            local_addr   = '0;
            decode_error = 1'b1;
        end
    end

endmodule