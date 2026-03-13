//============================================================================
// sys_ctrl.sv — System Control Peripheral
//
// Provides system identification and boot configuration registers.
// Critical for multi-core: each core reads HART_ID to determine identity.
//
// Registers:
//   0x00 HART_ID    R  — Hardware thread ID (parameterized per core)
//   0x04 NUM_HARTS  R  — Total number of harts in the system
//   0x08 BOOT_ADDR  RW — Boot address (writable for warm-boot redirection)
//   0x0C SCRATCH    RW — General-purpose scratch register
//============================================================================

module sys_ctrl
    import soc_pkg::*;
#(
    parameter int HART_ID   = 0,
    parameter int NUM_HARTS = 1,
    parameter logic [31:0] DEFAULT_BOOT_ADDR = 32'h0000_0000
)(
    input  logic        clk,
    input  logic        rst_n,

    // Register bus interface
    input  logic [31:0] addr,
    input  logic [31:0] wdata,
    input  logic        rd_en,
    input  logic        wr_en,
    input  logic [3:0]  be,
    output logic [31:0] rdata,
    output logic        valid
);

    // -----------------------------------------------------------------------
    // Writable registers
    // -----------------------------------------------------------------------
    logic [31:0] boot_addr;
    logic [31:0] scratch;

    logic [7:0] reg_addr;
    assign reg_addr = addr[7:0];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            boot_addr <= DEFAULT_BOOT_ADDR;
            scratch   <= '0;
        end else if (wr_en) begin
            case (reg_addr)
                SYSCTRL_BOOT_ADDR: begin
                    if (be[0]) boot_addr[7:0]   <= wdata[7:0];
                    if (be[1]) boot_addr[15:8]  <= wdata[15:8];
                    if (be[2]) boot_addr[23:16] <= wdata[23:16];
                    if (be[3]) boot_addr[31:24] <= wdata[31:24];
                end
                SYSCTRL_SCRATCH: begin
                    if (be[0]) scratch[7:0]   <= wdata[7:0];
                    if (be[1]) scratch[15:8]  <= wdata[15:8];
                    if (be[2]) scratch[23:16] <= wdata[23:16];
                    if (be[3]) scratch[31:24] <= wdata[31:24];
                end
                default: ;
            endcase
        end
    end

    // Combinational read
    always_comb begin
        valid = rd_en;
        case (reg_addr)
            SYSCTRL_HART_ID:   rdata = HART_ID[31:0];
            SYSCTRL_NUM_HARTS: rdata = NUM_HARTS[31:0];
            SYSCTRL_BOOT_ADDR: rdata = boot_addr;
            SYSCTRL_SCRATCH:   rdata = scratch;
            default:           rdata = '0;
        endcase
    end

endmodule