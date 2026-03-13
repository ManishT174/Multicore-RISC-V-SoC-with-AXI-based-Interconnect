//============================================================================
// bus_interconnect.sv — Simple Single-Master Bus Interconnect
//
// Routes one master port to N slave ports based on address decoding.
// Multiplexes slave read-data and valid signals back to the master.
//
// This is the single-core interconnect. For multi-core, the AXI
// crossbar (built in rtl/axi/) replaces this module.
//============================================================================

module bus_interconnect
    import soc_pkg::*;
(
    input  logic        clk,
    input  logic        rst_n,

    // Master port (from core data interface)
    input  logic [31:0] master_addr,
    input  logic [31:0] master_wdata,
    input  logic        master_rd,
    input  logic        master_wr,
    input  logic [3:0]  master_be,
    output logic [31:0] master_rdata,
    output logic        master_valid,

    // Slave ports — directly wired to peripherals
    // ROM
    output logic [31:0] rom_addr,
    output logic        rom_rd,
    input  logic [31:0] rom_rdata,
    input  logic        rom_valid,

    // RAM
    output logic [31:0] ram_addr,
    output logic [31:0] ram_wdata,
    output logic        ram_rd,
    output logic        ram_wr,
    output logic [3:0]  ram_be,
    input  logic [31:0] ram_rdata,
    input  logic        ram_valid,

    // UART
    output logic [31:0] uart_addr,
    output logic [31:0] uart_wdata,
    output logic        uart_rd,
    output logic        uart_wr,
    output logic [3:0]  uart_be,
    input  logic [31:0] uart_rdata,
    input  logic        uart_valid,

    // Timer
    output logic [31:0] timer_addr,
    output logic [31:0] timer_wdata,
    output logic        timer_rd,
    output logic        timer_wr,
    output logic [3:0]  timer_be,
    input  logic [31:0] timer_rdata,
    input  logic        timer_valid,

    // System Control
    output logic [31:0] sysctrl_addr,
    output logic [31:0] sysctrl_wdata,
    output logic        sysctrl_rd,
    output logic        sysctrl_wr,
    output logic [3:0]  sysctrl_be,
    input  logic [31:0] sysctrl_rdata,
    input  logic        sysctrl_valid
);

    // -----------------------------------------------------------------------
    // Address decode
    // -----------------------------------------------------------------------
    slave_id_t  slave_sel;
    logic [31:0] local_addr;
    logic        decode_error;

    addr_decoder u_decoder (
        .addr         (master_addr),
        .slave_sel    (slave_sel),
        .local_addr   (local_addr),
        .decode_error (decode_error)
    );

    // Remember which slave was selected (for response mux, 1 cycle later)
    slave_id_t slave_sel_r;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            slave_sel_r <= SLAVE_NONE;
        else if (master_rd || master_wr)
            slave_sel_r <= slave_sel;
    end

    // -----------------------------------------------------------------------
    // Request routing (directly wire based on decode)
    // -----------------------------------------------------------------------
    // Common write data and byte enables fan out to all slaves
    // (only the selected slave's wr/rd enable is asserted)

    // ROM (read-only)
    assign rom_addr = local_addr;
    assign rom_rd   = master_rd && (slave_sel == SLAVE_ROM);

    // RAM
    assign ram_addr  = local_addr;
    assign ram_wdata = master_wdata;
    assign ram_be    = master_be;
    assign ram_rd    = master_rd && (slave_sel == SLAVE_RAM);
    assign ram_wr    = master_wr && (slave_sel == SLAVE_RAM);

    // UART
    assign uart_addr  = local_addr;
    assign uart_wdata = master_wdata;
    assign uart_be    = master_be;
    assign uart_rd    = master_rd && (slave_sel == SLAVE_UART);
    assign uart_wr    = master_wr && (slave_sel == SLAVE_UART);

    // Timer
    assign timer_addr  = local_addr;
    assign timer_wdata = master_wdata;
    assign timer_be    = master_be;
    assign timer_rd    = master_rd && (slave_sel == SLAVE_TIMER);
    assign timer_wr    = master_wr && (slave_sel == SLAVE_TIMER);

    // System Control
    assign sysctrl_addr  = local_addr;
    assign sysctrl_wdata = master_wdata;
    assign sysctrl_be    = master_be;
    assign sysctrl_rd    = master_rd && (slave_sel == SLAVE_SYSCTRL);
    assign sysctrl_wr    = master_wr && (slave_sel == SLAVE_SYSCTRL);

    // -----------------------------------------------------------------------
    // Response mux (combinational — slave reads are also combinational)
    // -----------------------------------------------------------------------
    always_comb begin
        case (slave_sel)
            SLAVE_ROM:     begin master_rdata = rom_rdata;     master_valid = rom_valid;     end
            SLAVE_RAM:     begin master_rdata = ram_rdata;     master_valid = ram_valid;     end
            SLAVE_UART:    begin master_rdata = uart_rdata;    master_valid = uart_valid;    end
            SLAVE_TIMER:   begin master_rdata = timer_rdata;   master_valid = timer_valid;   end
            SLAVE_SYSCTRL: begin master_rdata = sysctrl_rdata; master_valid = sysctrl_valid; end
            default:       begin master_rdata = 32'hDEAD_BEEF; master_valid = 1'b1;          end
        endcase
    end

endmodule