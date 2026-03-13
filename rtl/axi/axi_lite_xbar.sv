//============================================================================
// axi_lite_xbar.sv — AXI4-Lite Crossbar (Icarus-Compatible)
//
// Fixed 4 masters × 5 slaves. Uses flat signal vectors to avoid
// Icarus issues with dynamic unpacked array indexing.
//
// Each slave port has write and read round-robin arbiters.
// One outstanding transaction per master.
//============================================================================

module axi_lite_xbar
    import axi_pkg::*;
    import soc_pkg::*;
#(
    parameter int NUM_MASTERS = 4,
    parameter int NUM_SLAVES  = 5
)(
    input  logic clk,
    input  logic rst_n,

    // ===== Master port 0 =====
    input  logic [31:0] m0_awaddr,  input  logic [2:0]  m0_awprot,
    input  logic        m0_awvalid, output logic         m0_awready,
    input  logic [31:0] m0_wdata,   input  logic [3:0]  m0_wstrb,
    input  logic        m0_wvalid,  output logic         m0_wready,
    output logic [1:0]  m0_bresp,   output logic         m0_bvalid,
    input  logic        m0_bready,
    input  logic [31:0] m0_araddr,  input  logic [2:0]  m0_arprot,
    input  logic        m0_arvalid, output logic         m0_arready,
    output logic [31:0] m0_rdata,   output logic [1:0]  m0_rresp,
    output logic        m0_rvalid,  input  logic         m0_rready,

    // ===== Master port 1 =====
    input  logic [31:0] m1_awaddr,  input  logic [2:0]  m1_awprot,
    input  logic        m1_awvalid, output logic         m1_awready,
    input  logic [31:0] m1_wdata,   input  logic [3:0]  m1_wstrb,
    input  logic        m1_wvalid,  output logic         m1_wready,
    output logic [1:0]  m1_bresp,   output logic         m1_bvalid,
    input  logic        m1_bready,
    input  logic [31:0] m1_araddr,  input  logic [2:0]  m1_arprot,
    input  logic        m1_arvalid, output logic         m1_arready,
    output logic [31:0] m1_rdata,   output logic [1:0]  m1_rresp,
    output logic        m1_rvalid,  input  logic         m1_rready,

    // ===== Master port 2 =====
    input  logic [31:0] m2_awaddr,  input  logic [2:0]  m2_awprot,
    input  logic        m2_awvalid, output logic         m2_awready,
    input  logic [31:0] m2_wdata,   input  logic [3:0]  m2_wstrb,
    input  logic        m2_wvalid,  output logic         m2_wready,
    output logic [1:0]  m2_bresp,   output logic         m2_bvalid,
    input  logic        m2_bready,
    input  logic [31:0] m2_araddr,  input  logic [2:0]  m2_arprot,
    input  logic        m2_arvalid, output logic         m2_arready,
    output logic [31:0] m2_rdata,   output logic [1:0]  m2_rresp,
    output logic        m2_rvalid,  input  logic         m2_rready,

    // ===== Master port 3 =====
    input  logic [31:0] m3_awaddr,  input  logic [2:0]  m3_awprot,
    input  logic        m3_awvalid, output logic         m3_awready,
    input  logic [31:0] m3_wdata,   input  logic [3:0]  m3_wstrb,
    input  logic        m3_wvalid,  output logic         m3_wready,
    output logic [1:0]  m3_bresp,   output logic         m3_bvalid,
    input  logic        m3_bready,
    input  logic [31:0] m3_araddr,  input  logic [2:0]  m3_arprot,
    input  logic        m3_arvalid, output logic         m3_arready,
    output logic [31:0] m3_rdata,   output logic [1:0]  m3_rresp,
    output logic        m3_rvalid,  input  logic         m3_rready,

    // ===== Slave ports (directly connected to slave bridges) =====
    // Slave 0 (ROM)
    output logic [31:0] s0_awaddr,  output logic [2:0]  s0_awprot,
    output logic        s0_awvalid, input  logic         s0_awready,
    output logic [31:0] s0_wdata,   output logic [3:0]  s0_wstrb,
    output logic        s0_wvalid,  input  logic         s0_wready,
    input  logic [1:0]  s0_bresp,   input  logic         s0_bvalid,
    output logic        s0_bready,
    output logic [31:0] s0_araddr,  output logic [2:0]  s0_arprot,
    output logic        s0_arvalid, input  logic         s0_arready,
    input  logic [31:0] s0_rdata,   input  logic [1:0]  s0_rresp,
    input  logic        s0_rvalid,  output logic         s0_rready,

    // Slave 1 (RAM)
    output logic [31:0] s1_awaddr,  output logic [2:0]  s1_awprot,
    output logic        s1_awvalid, input  logic         s1_awready,
    output logic [31:0] s1_wdata,   output logic [3:0]  s1_wstrb,
    output logic        s1_wvalid,  input  logic         s1_wready,
    input  logic [1:0]  s1_bresp,   input  logic         s1_bvalid,
    output logic        s1_bready,
    output logic [31:0] s1_araddr,  output logic [2:0]  s1_arprot,
    output logic        s1_arvalid, input  logic         s1_arready,
    input  logic [31:0] s1_rdata,   input  logic [1:0]  s1_rresp,
    input  logic        s1_rvalid,  output logic         s1_rready,

    // Slave 2 (UART)
    output logic [31:0] s2_awaddr,  output logic [2:0]  s2_awprot,
    output logic        s2_awvalid, input  logic         s2_awready,
    output logic [31:0] s2_wdata,   output logic [3:0]  s2_wstrb,
    output logic        s2_wvalid,  input  logic         s2_wready,
    input  logic [1:0]  s2_bresp,   input  logic         s2_bvalid,
    output logic        s2_bready,
    output logic [31:0] s2_araddr,  output logic [2:0]  s2_arprot,
    output logic        s2_arvalid, input  logic         s2_arready,
    input  logic [31:0] s2_rdata,   input  logic [1:0]  s2_rresp,
    input  logic        s2_rvalid,  output logic         s2_rready,

    // Slave 3 (Timer)
    output logic [31:0] s3_awaddr,  output logic [2:0]  s3_awprot,
    output logic        s3_awvalid, input  logic         s3_awready,
    output logic [31:0] s3_wdata,   output logic [3:0]  s3_wstrb,
    output logic        s3_wvalid,  input  logic         s3_wready,
    input  logic [1:0]  s3_bresp,   input  logic         s3_bvalid,
    output logic        s3_bready,
    output logic [31:0] s3_araddr,  output logic [2:0]  s3_arprot,
    output logic        s3_arvalid, input  logic         s3_arready,
    input  logic [31:0] s3_rdata,   input  logic [1:0]  s3_rresp,
    input  logic        s3_rvalid,  output logic         s3_rready,

    // Slave 4 (SYSCTRL)
    output logic [31:0] s4_awaddr,  output logic [2:0]  s4_awprot,
    output logic        s4_awvalid, input  logic         s4_awready,
    output logic [31:0] s4_wdata,   output logic [3:0]  s4_wstrb,
    output logic        s4_wvalid,  input  logic         s4_wready,
    input  logic [1:0]  s4_bresp,   input  logic         s4_bvalid,
    output logic        s4_bready,
    output logic [31:0] s4_araddr,  output logic [2:0]  s4_arprot,
    output logic        s4_arvalid, input  logic         s4_arready,
    input  logic [31:0] s4_rdata,   input  logic [1:0]  s4_rresp,
    input  logic        s4_rvalid,  output logic         s4_rready
);

    localparam int M = NUM_MASTERS;
    localparam int S = NUM_SLAVES;

    // -----------------------------------------------------------------------
    // Internal flat arrays (packed, Icarus-friendly)
    // -----------------------------------------------------------------------
    // Master inputs gathered into flat arrays
    wire [31:0] mi_awaddr [0:M-1];
    wire [2:0]  mi_awprot [0:M-1];
    wire        mi_awvalid[0:M-1];
    wire [31:0] mi_wdata  [0:M-1];
    wire [3:0]  mi_wstrb  [0:M-1];
    wire        mi_wvalid [0:M-1];
    wire        mi_bready [0:M-1];
    wire [31:0] mi_araddr [0:M-1];
    wire [2:0]  mi_arprot [0:M-1];
    wire        mi_arvalid[0:M-1];
    wire        mi_rready [0:M-1];

    assign mi_awaddr[0] = m0_awaddr; assign mi_awaddr[1] = m1_awaddr;
    assign mi_awaddr[2] = m2_awaddr; assign mi_awaddr[3] = m3_awaddr;
    assign mi_awprot[0] = m0_awprot; assign mi_awprot[1] = m1_awprot;
    assign mi_awprot[2] = m2_awprot; assign mi_awprot[3] = m3_awprot;
    assign mi_awvalid[0]= m0_awvalid;assign mi_awvalid[1]= m1_awvalid;
    assign mi_awvalid[2]= m2_awvalid;assign mi_awvalid[3]= m3_awvalid;
    assign mi_wdata[0]  = m0_wdata;  assign mi_wdata[1]  = m1_wdata;
    assign mi_wdata[2]  = m2_wdata;  assign mi_wdata[3]  = m3_wdata;
    assign mi_wstrb[0]  = m0_wstrb;  assign mi_wstrb[1]  = m1_wstrb;
    assign mi_wstrb[2]  = m2_wstrb;  assign mi_wstrb[3]  = m3_wstrb;
    assign mi_wvalid[0] = m0_wvalid; assign mi_wvalid[1] = m1_wvalid;
    assign mi_wvalid[2] = m2_wvalid; assign mi_wvalid[3] = m3_wvalid;
    assign mi_bready[0] = m0_bready; assign mi_bready[1] = m1_bready;
    assign mi_bready[2] = m2_bready; assign mi_bready[3] = m3_bready;
    assign mi_araddr[0] = m0_araddr; assign mi_araddr[1] = m1_araddr;
    assign mi_araddr[2] = m2_araddr; assign mi_araddr[3] = m3_araddr;
    assign mi_arprot[0] = m0_arprot; assign mi_arprot[1] = m1_arprot;
    assign mi_arprot[2] = m2_arprot; assign mi_arprot[3] = m3_arprot;
    assign mi_arvalid[0]= m0_arvalid;assign mi_arvalid[1]= m1_arvalid;
    assign mi_arvalid[2]= m2_arvalid;assign mi_arvalid[3]= m3_arvalid;
    assign mi_rready[0] = m0_rready; assign mi_rready[1] = m1_rready;
    assign mi_rready[2] = m2_rready; assign mi_rready[3] = m3_rready;

    // Master outputs
    reg         mo_awready[0:M-1], mo_wready[0:M-1], mo_bvalid[0:M-1];
    reg  [1:0]  mo_bresp  [0:M-1];
    reg         mo_arready[0:M-1], mo_rvalid[0:M-1];
    reg  [31:0] mo_rdata  [0:M-1];
    reg  [1:0]  mo_rresp  [0:M-1];

    assign m0_awready = mo_awready[0]; assign m1_awready = mo_awready[1];
    assign m2_awready = mo_awready[2]; assign m3_awready = mo_awready[3];
    assign m0_wready  = mo_wready[0];  assign m1_wready  = mo_wready[1];
    assign m2_wready  = mo_wready[2];  assign m3_wready  = mo_wready[3];
    assign m0_bresp   = mo_bresp[0];   assign m1_bresp   = mo_bresp[1];
    assign m2_bresp   = mo_bresp[2];   assign m3_bresp   = mo_bresp[3];
    assign m0_bvalid  = mo_bvalid[0];  assign m1_bvalid  = mo_bvalid[1];
    assign m2_bvalid  = mo_bvalid[2];  assign m3_bvalid  = mo_bvalid[3];
    assign m0_arready = mo_arready[0]; assign m1_arready = mo_arready[1];
    assign m2_arready = mo_arready[2]; assign m3_arready = mo_arready[3];
    assign m0_rdata   = mo_rdata[0];   assign m1_rdata   = mo_rdata[1];
    assign m2_rdata   = mo_rdata[2];   assign m3_rdata   = mo_rdata[3];
    assign m0_rresp   = mo_rresp[0];   assign m1_rresp   = mo_rresp[1];
    assign m2_rresp   = mo_rresp[2];   assign m3_rresp   = mo_rresp[3];
    assign m0_rvalid  = mo_rvalid[0];  assign m1_rvalid  = mo_rvalid[1];
    assign m2_rvalid  = mo_rvalid[2];  assign m3_rvalid  = mo_rvalid[3];

    // Slave inputs gathered
    wire        si_awready[0:S-1], si_wready[0:S-1], si_bvalid[0:S-1];
    wire [1:0]  si_bresp  [0:S-1];
    wire        si_arready[0:S-1], si_rvalid[0:S-1];
    wire [31:0] si_rdata  [0:S-1];
    wire [1:0]  si_rresp  [0:S-1];

    assign si_awready[0]=s0_awready; assign si_awready[1]=s1_awready;
    assign si_awready[2]=s2_awready; assign si_awready[3]=s3_awready; assign si_awready[4]=s4_awready;
    assign si_wready[0] =s0_wready;  assign si_wready[1] =s1_wready;
    assign si_wready[2] =s2_wready;  assign si_wready[3] =s3_wready;  assign si_wready[4] =s4_wready;
    assign si_bresp[0]  =s0_bresp;   assign si_bresp[1]  =s1_bresp;
    assign si_bresp[2]  =s2_bresp;   assign si_bresp[3]  =s3_bresp;   assign si_bresp[4]  =s4_bresp;
    assign si_bvalid[0] =s0_bvalid;  assign si_bvalid[1] =s1_bvalid;
    assign si_bvalid[2] =s2_bvalid;  assign si_bvalid[3] =s3_bvalid;  assign si_bvalid[4] =s4_bvalid;
    assign si_arready[0]=s0_arready; assign si_arready[1]=s1_arready;
    assign si_arready[2]=s2_arready; assign si_arready[3]=s3_arready; assign si_arready[4]=s4_arready;
    assign si_rdata[0]  =s0_rdata;   assign si_rdata[1]  =s1_rdata;
    assign si_rdata[2]  =s2_rdata;   assign si_rdata[3]  =s3_rdata;   assign si_rdata[4]  =s4_rdata;
    assign si_rresp[0]  =s0_rresp;   assign si_rresp[1]  =s1_rresp;
    assign si_rresp[2]  =s2_rresp;   assign si_rresp[3]  =s3_rresp;   assign si_rresp[4]  =s4_rresp;
    assign si_rvalid[0] =s0_rvalid;  assign si_rvalid[1] =s1_rvalid;
    assign si_rvalid[2] =s2_rvalid;  assign si_rvalid[3] =s3_rvalid;  assign si_rvalid[4] =s4_rvalid;

    // Slave outputs
    reg [31:0]  so_awaddr [0:S-1]; reg [2:0] so_awprot[0:S-1]; reg so_awvalid[0:S-1];
    reg [31:0]  so_wdata  [0:S-1]; reg [3:0] so_wstrb [0:S-1]; reg so_wvalid [0:S-1];
    reg         so_bready [0:S-1];
    reg [31:0]  so_araddr [0:S-1]; reg [2:0] so_arprot[0:S-1]; reg so_arvalid[0:S-1];
    reg         so_rready [0:S-1];

    assign s0_awaddr=so_awaddr[0]; assign s1_awaddr=so_awaddr[1]; assign s2_awaddr=so_awaddr[2]; assign s3_awaddr=so_awaddr[3]; assign s4_awaddr=so_awaddr[4];
    assign s0_awprot=so_awprot[0]; assign s1_awprot=so_awprot[1]; assign s2_awprot=so_awprot[2]; assign s3_awprot=so_awprot[3]; assign s4_awprot=so_awprot[4];
    assign s0_awvalid=so_awvalid[0]; assign s1_awvalid=so_awvalid[1]; assign s2_awvalid=so_awvalid[2]; assign s3_awvalid=so_awvalid[3]; assign s4_awvalid=so_awvalid[4];
    assign s0_wdata=so_wdata[0]; assign s1_wdata=so_wdata[1]; assign s2_wdata=so_wdata[2]; assign s3_wdata=so_wdata[3]; assign s4_wdata=so_wdata[4];
    assign s0_wstrb=so_wstrb[0]; assign s1_wstrb=so_wstrb[1]; assign s2_wstrb=so_wstrb[2]; assign s3_wstrb=so_wstrb[3]; assign s4_wstrb=so_wstrb[4];
    assign s0_wvalid=so_wvalid[0]; assign s1_wvalid=so_wvalid[1]; assign s2_wvalid=so_wvalid[2]; assign s3_wvalid=so_wvalid[3]; assign s4_wvalid=so_wvalid[4];
    assign s0_bready=so_bready[0]; assign s1_bready=so_bready[1]; assign s2_bready=so_bready[2]; assign s3_bready=so_bready[3]; assign s4_bready=so_bready[4];
    assign s0_araddr=so_araddr[0]; assign s1_araddr=so_araddr[1]; assign s2_araddr=so_araddr[2]; assign s3_araddr=so_araddr[3]; assign s4_araddr=so_araddr[4];
    assign s0_arprot=so_arprot[0]; assign s1_arprot=so_arprot[1]; assign s2_arprot=so_arprot[2]; assign s3_arprot=so_arprot[3]; assign s4_arprot=so_arprot[4];
    assign s0_arvalid=so_arvalid[0]; assign s1_arvalid=so_arvalid[1]; assign s2_arvalid=so_arvalid[2]; assign s3_arvalid=so_arvalid[3]; assign s4_arvalid=so_arvalid[4];
    assign s0_rready=so_rready[0]; assign s1_rready=so_rready[1]; assign s2_rready=so_rready[2]; assign s3_rready=so_rready[3]; assign s4_rready=so_rready[4];

    // -----------------------------------------------------------------------
    // Address decode: which slave does each master want?
    // -----------------------------------------------------------------------
    reg [2:0] m_wr_target [0:M-1];
    reg [2:0] m_rd_target [0:M-1];

    function automatic [2:0] decode_addr(input [31:0] addr);
        if      (addr >= ROM_BASE     && addr < ROM_BASE + ROM_SIZE)     return 3'd0;
        else if (addr >= RAM_BASE     && addr < RAM_BASE + RAM_SIZE)     return 3'd1;
        else if (addr >= UART_BASE    && addr < UART_BASE + UART_SIZE)   return 3'd2;
        else if (addr >= TIMER_BASE   && addr < TIMER_BASE + TIMER_SIZE) return 3'd3;
        else if (addr >= SYSCTRL_BASE && addr < SYSCTRL_BASE+SYSCTRL_SIZE) return 3'd4;
        else return 3'd7; // Invalid
    endfunction

    always_comb begin
        for (int mi = 0; mi < M; mi++) begin
            m_wr_target[mi] = decode_addr(mi_awaddr[mi]);
            m_rd_target[mi] = decode_addr(mi_araddr[mi]);
        end
    end

    // -----------------------------------------------------------------------
    // Per-master state: track active transaction
    // -----------------------------------------------------------------------
    typedef enum logic [1:0] { MS_IDLE, MS_WRITE, MS_READ } mst_t;
    mst_t m_state [0:M-1];
    reg [2:0] m_active_slave [0:M-1];

    // -----------------------------------------------------------------------
    // Per-slave write arbiters (4 requesters per slave)
    // -----------------------------------------------------------------------
    logic [M-1:0] wr_req [0:S-1];
    logic [M-1:0] wr_grant [0:S-1];
    logic         wr_gv [0:S-1];
    logic [1:0]   wr_gi [0:S-1];

    logic [M-1:0] rd_req [0:S-1];
    logic [M-1:0] rd_grant [0:S-1];
    logic         rd_gv [0:S-1];
    logic [1:0]   rd_gi [0:S-1];

    // Build request vectors
    always_comb begin
        for (int si = 0; si < S; si++) begin
            for (int mi = 0; mi < M; mi++) begin
                wr_req[si][mi] = mi_awvalid[mi] && (m_wr_target[mi] == si[2:0]) &&
                                 (m_state[mi] == MS_IDLE);
                rd_req[si][mi] = mi_arvalid[mi] && (m_rd_target[mi] == si[2:0]) &&
                                 (m_state[mi] == MS_IDLE) && !mi_awvalid[mi]; // wr priority
            end
        end
    end

    generate
        for (genvar si = 0; si < S; si++) begin : gen_arb
            rr_arbiter #(.N(M)) u_wr_arb (
                .clk(clk), .rst_n(rst_n),
                .req(wr_req[si]), .grant(wr_grant[si]),
                .grant_valid(wr_gv[si]), .grant_idx(wr_gi[si])
            );
            rr_arbiter #(.N(M)) u_rd_arb (
                .clk(clk), .rst_n(rst_n),
                .req(rd_req[si]), .grant(rd_grant[si]),
                .grant_valid(rd_gv[si]), .grant_idx(rd_gi[si])
            );
        end
    endgenerate

    // -----------------------------------------------------------------------
    // Master state machine
    // -----------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        for (int mi = 0; mi < M; mi++) begin
            if (!rst_n) begin
                m_state[mi] <= MS_IDLE;
                m_active_slave[mi] <= 3'd0;
            end else begin
                case (m_state[mi])
                    MS_IDLE: begin
                        // Check write grants
                        for (int si = 0; si < S; si++) begin
                            if (wr_grant[si][mi]) begin
                                m_state[mi] <= MS_WRITE;
                                m_active_slave[mi] <= si[2:0];
                            end
                        end
                        // Check read grants (only if no write grant)
                        if (m_state[mi] == MS_IDLE) begin
                            for (int si = 0; si < S; si++) begin
                                if (rd_grant[si][mi]) begin
                                    m_state[mi] <= MS_READ;
                                    m_active_slave[mi] <= si[2:0];
                                end
                            end
                        end
                    end
                    MS_WRITE: if (mo_bvalid[mi] && mi_bready[mi]) m_state[mi] <= MS_IDLE;
                    MS_READ:  if (mo_rvalid[mi] && mi_rready[mi]) m_state[mi] <= MS_IDLE;
                    default:  m_state[mi] <= MS_IDLE;
                endcase
            end
        end
    end

    // -----------------------------------------------------------------------
    // Request mux: route granted master → target slave
    // -----------------------------------------------------------------------
    always_comb begin
        for (int si = 0; si < S; si++) begin
            so_awaddr[si]  = '0; so_awprot[si]  = '0; so_awvalid[si] = 1'b0;
            so_wdata[si]   = '0; so_wstrb[si]   = '0; so_wvalid[si]  = 1'b0;
            so_bready[si]  = 1'b0;
            so_araddr[si]  = '0; so_arprot[si]  = '0; so_arvalid[si] = 1'b0;
            so_rready[si]  = 1'b0;
        end

        for (int mi = 0; mi < M; mi++) begin
            if (m_state[mi] == MS_WRITE) begin
                for (int si = 0; si < S; si++) begin
                    if (m_active_slave[mi] == si[2:0]) begin
                        so_awaddr[si]  = mi_awaddr[mi];
                        so_awprot[si]  = mi_awprot[mi];
                        so_awvalid[si] = mi_awvalid[mi];
                        so_wdata[si]   = mi_wdata[mi];
                        so_wstrb[si]   = mi_wstrb[mi];
                        so_wvalid[si]  = mi_wvalid[mi];
                        so_bready[si]  = mi_bready[mi];
                    end
                end
            end else if (m_state[mi] == MS_READ) begin
                for (int si = 0; si < S; si++) begin
                    if (m_active_slave[mi] == si[2:0]) begin
                        so_araddr[si]  = mi_araddr[mi];
                        so_arprot[si]  = mi_arprot[mi];
                        so_arvalid[si] = mi_arvalid[mi];
                        so_rready[si]  = mi_rready[mi];
                    end
                end
            end
        end
    end

    // -----------------------------------------------------------------------
    // Response mux: route slave response → requesting master
    // -----------------------------------------------------------------------
    always_comb begin
        for (int mi = 0; mi < M; mi++) begin
            mo_awready[mi] = 1'b0; mo_wready[mi] = 1'b0;
            mo_bresp[mi]   = 2'b00; mo_bvalid[mi] = 1'b0;
            mo_arready[mi] = 1'b0;
            mo_rdata[mi]   = '0; mo_rresp[mi] = 2'b00; mo_rvalid[mi] = 1'b0;
        end

        for (int mi = 0; mi < M; mi++) begin
            if (m_state[mi] == MS_WRITE) begin
                for (int si = 0; si < S; si++) begin
                    if (m_active_slave[mi] == si[2:0]) begin
                        mo_awready[mi] = si_awready[si];
                        mo_wready[mi]  = si_wready[si];
                        mo_bresp[mi]   = si_bresp[si];
                        mo_bvalid[mi]  = si_bvalid[si];
                    end
                end
            end else if (m_state[mi] == MS_READ) begin
                for (int si = 0; si < S; si++) begin
                    if (m_active_slave[mi] == si[2:0]) begin
                        mo_arready[mi] = si_arready[si];
                        mo_rdata[mi]   = si_rdata[si];
                        mo_rresp[mi]   = si_rresp[si];
                        mo_rvalid[mi]  = si_rvalid[si];
                    end
                end
            end
        end
    end

endmodule