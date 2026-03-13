//============================================================================
// uart.sv — UART Transmitter Peripheral
//
// Features:
//   - 8N1 format, configurable baud rate via divisor register
//   - 8-entry TX FIFO
//   - RX stub (always returns 0, ready for future expansion)
//   - Register-mapped interface matching soc_pkg offsets
//   - Simulation mode: $write characters to console for visibility
//
// Registers:
//   0x00 TX_DATA    [7:0]  W — Write byte to TX FIFO
//   0x04 TX_STATUS  [0]    R — TX busy, [1] TX FIFO full
//   0x08 RX_DATA    [7:0]  R — RX data (stub: 0)
//   0x0C RX_STATUS  [0]    R — RX data valid (stub: 0)
//   0x10 CTRL       [15:0] RW — Baud divisor (clk_freq / baud_rate)
//============================================================================

module uart
    import soc_pkg::*;
#(
    parameter int DEFAULT_BAUD_DIV = 868   // 100MHz / 115200 ≈ 868
)(
    input  logic        clk,
    input  logic        rst_n,

    // Register bus interface
    input  logic [31:0] addr,       // Local address (byte offset)
    input  logic [31:0] wdata,
    input  logic        rd_en,
    input  logic        wr_en,
    input  logic [3:0]  be,
    output logic [31:0] rdata,
    output logic        valid,

    // Physical UART signals
    output logic        uart_tx,
    input  logic        uart_rx,     // Stub: not used yet

    // Interrupt
    output logic        irq_tx_done
);

    // -----------------------------------------------------------------------
    // Baud rate generator
    // -----------------------------------------------------------------------
    logic [15:0] baud_div;
    logic [15:0] baud_cnt;
    logic        baud_tick;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            baud_cnt  <= '0;
            baud_tick <= 1'b0;
        end else if (baud_cnt == baud_div - 1) begin
            baud_cnt  <= '0;
            baud_tick <= 1'b1;
        end else begin
            baud_cnt  <= baud_cnt + 1;
            baud_tick <= 1'b0;
        end
    end

    // -----------------------------------------------------------------------
    // TX FIFO (simple shift register, 8 entries)
    // -----------------------------------------------------------------------
    logic [7:0]  tx_fifo [0:7];
    logic [3:0]  tx_fifo_wptr, tx_fifo_rptr;
    logic [3:0]  tx_fifo_count;
    logic        tx_fifo_full, tx_fifo_empty;
    logic        tx_fifo_push, tx_fifo_pop;

    assign tx_fifo_full  = (tx_fifo_count == 4'd8);
    assign tx_fifo_empty = (tx_fifo_count == 4'd0);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_fifo_wptr  <= '0;
            tx_fifo_rptr  <= '0;
            tx_fifo_count <= '0;
        end else begin
            case ({tx_fifo_push && !tx_fifo_full, tx_fifo_pop && !tx_fifo_empty})
                2'b10: begin
                    tx_fifo_wptr  <= (tx_fifo_wptr + 1) & 4'h7;
                    tx_fifo_count <= tx_fifo_count + 1;
                end
                2'b01: begin
                    tx_fifo_rptr  <= (tx_fifo_rptr + 1) & 4'h7;
                    tx_fifo_count <= tx_fifo_count - 1;
                end
                2'b11: begin
                    tx_fifo_wptr  <= (tx_fifo_wptr + 1) & 4'h7;
                    tx_fifo_rptr  <= (tx_fifo_rptr + 1) & 4'h7;
                    // Count stays same
                end
                default: ; // No change
            endcase
        end
    end

    always_ff @(posedge clk) begin
        if (tx_fifo_push && !tx_fifo_full)
            tx_fifo[tx_fifo_wptr[2:0]] <= wdata[7:0];
    end

    wire [7:0] tx_fifo_head = tx_fifo[tx_fifo_rptr[2:0]];

    // -----------------------------------------------------------------------
    // TX Shift Register (8N1: start + 8 data + stop = 10 bits)
    // -----------------------------------------------------------------------
    typedef enum logic [1:0] {
        TX_IDLE,
        TX_START,
        TX_DATA,
        TX_STOP
    } tx_state_t;

    tx_state_t   tx_state;
    logic [7:0]  tx_shift;
    logic [2:0]  tx_bit_cnt;
    logic        tx_busy;

    assign tx_busy = (tx_state != TX_IDLE);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_state   <= TX_IDLE;
            tx_shift   <= '0;
            tx_bit_cnt <= '0;
            uart_tx    <= 1'b1; // Idle high
            tx_fifo_pop <= 1'b0;
            irq_tx_done <= 1'b0;
        end else begin
            tx_fifo_pop <= 1'b0;
            irq_tx_done <= 1'b0;

            case (tx_state)
                TX_IDLE: begin
                    uart_tx <= 1'b1;
                    if (!tx_fifo_empty) begin
                        tx_shift    <= tx_fifo_head;
                        tx_fifo_pop <= 1'b1;
                        tx_state    <= TX_START;
                        // Simulation: print character to console
                        // synthesis translate_off
                        $write("%c", tx_fifo_head);
                        // synthesis translate_on
                    end
                end

                TX_START: begin
                    if (baud_tick) begin
                        uart_tx    <= 1'b0; // Start bit
                        tx_state   <= TX_DATA;
                        tx_bit_cnt <= '0;
                    end
                end

                TX_DATA: begin
                    if (baud_tick) begin
                        uart_tx  <= tx_shift[0];
                        tx_shift <= {1'b0, tx_shift[7:1]};
                        if (tx_bit_cnt == 3'd7)
                            tx_state <= TX_STOP;
                        else
                            tx_bit_cnt <= tx_bit_cnt + 1;
                    end
                end

                TX_STOP: begin
                    if (baud_tick) begin
                        uart_tx     <= 1'b1; // Stop bit
                        tx_state    <= TX_IDLE;
                        irq_tx_done <= 1'b1;
                    end
                end
            endcase
        end
    end

    // -----------------------------------------------------------------------
    // Register Read/Write
    // -----------------------------------------------------------------------
    logic [7:0] reg_addr;
    assign reg_addr = addr[7:0];

    // Write logic
    assign tx_fifo_push = wr_en && (reg_addr == UART_TX_DATA) && be[0];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            baud_div <= DEFAULT_BAUD_DIV[15:0];
        end else if (wr_en && (reg_addr == UART_CTRL)) begin
            if (be[0]) baud_div[7:0]  <= wdata[7:0];
            if (be[1]) baud_div[15:8] <= wdata[15:8];
        end
    end

    // Combinational read
    always_comb begin
        valid = rd_en;
        case (reg_addr)
            UART_TX_DATA:   rdata = '0;
            UART_TX_STATUS: rdata = {30'b0, tx_fifo_full, tx_busy};
            UART_RX_DATA:   rdata = '0;
            UART_RX_STATUS: rdata = '0;
            UART_CTRL:      rdata = {16'b0, baud_div};
            default:        rdata = '0;
        endcase
    end

endmodule