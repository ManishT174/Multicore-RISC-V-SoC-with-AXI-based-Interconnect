//============================================================================
// load_store_unit.v — Load Data Alignment & Store Data Formatting
//   - Extracts and sign-extends loaded data (LB, LH, LW, LBU, LHU)
//   - Formats store data and generates byte-enable mask (SB, SH, SW)
//============================================================================

`include "rv32i_defs.vh"

module load_store_unit (
    // Load path
    input  logic [2:0]  funct3,
    input  logic [1:0]  addr_lo,      // Address bits [1:0] for alignment
    input  logic [31:0] mem_rdata,     // Raw 32-bit word from memory
    output logic  [31:0] load_data,     // Aligned & sign-extended result

    // Store path
    input  logic [31:0] rs2_data,      // Data to store
    output logic  [31:0] store_data,    // Formatted data to memory
    output logic  [3:0]  store_be       // Byte enables
);

    // -----------------------------------------------------------------------
    // Load alignment & sign extension
    // -----------------------------------------------------------------------
    always_comb begin
        case (funct3)
            `FUNCT3_LB: begin
                case (addr_lo)
                    2'b00: load_data = {{24{mem_rdata[7]}},  mem_rdata[7:0]};
                    2'b01: load_data = {{24{mem_rdata[15]}}, mem_rdata[15:8]};
                    2'b10: load_data = {{24{mem_rdata[23]}}, mem_rdata[23:16]};
                    2'b11: load_data = {{24{mem_rdata[31]}}, mem_rdata[31:24]};
                endcase
            end
            `FUNCT3_LH: begin
                case (addr_lo[1])
                    1'b0: load_data = {{16{mem_rdata[15]}}, mem_rdata[15:0]};
                    1'b1: load_data = {{16{mem_rdata[31]}}, mem_rdata[31:16]};
                endcase
            end
            `FUNCT3_LW: begin
                load_data = mem_rdata;
            end
            `FUNCT3_LBU: begin
                case (addr_lo)
                    2'b00: load_data = {24'd0, mem_rdata[7:0]};
                    2'b01: load_data = {24'd0, mem_rdata[15:8]};
                    2'b10: load_data = {24'd0, mem_rdata[23:16]};
                    2'b11: load_data = {24'd0, mem_rdata[31:24]};
                endcase
            end
            `FUNCT3_LHU: begin
                case (addr_lo[1])
                    1'b0: load_data = {16'd0, mem_rdata[15:0]};
                    1'b1: load_data = {16'd0, mem_rdata[31:16]};
                endcase
            end
            default: load_data = mem_rdata;
        endcase
    end

    // -----------------------------------------------------------------------
    // Store data formatting & byte enables
    // -----------------------------------------------------------------------
    always_comb begin
        store_data = 32'd0;
        store_be   = 4'b0000;
        case (funct3)
            `FUNCT3_SB: begin
                case (addr_lo)
                    2'b00: begin store_data = {24'd0, rs2_data[7:0]};       store_be = 4'b0001; end
                    2'b01: begin store_data = {16'd0, rs2_data[7:0], 8'd0}; store_be = 4'b0010; end
                    2'b10: begin store_data = {8'd0, rs2_data[7:0], 16'd0}; store_be = 4'b0100; end
                    2'b11: begin store_data = {rs2_data[7:0], 24'd0};       store_be = 4'b1000; end
                endcase
            end
            `FUNCT3_SH: begin
                case (addr_lo[1])
                    1'b0: begin store_data = {16'd0, rs2_data[15:0]};       store_be = 4'b0011; end
                    1'b1: begin store_data = {rs2_data[15:0], 16'd0};       store_be = 4'b1100; end
                endcase
            end
            `FUNCT3_SW: begin
                store_data = rs2_data;
                store_be   = 4'b1111;
            end
            default: begin
                store_data = 32'd0;
                store_be   = 4'b0000;
            end
        endcase
    end

endmodule