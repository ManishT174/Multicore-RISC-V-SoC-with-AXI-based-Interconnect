//============================================================================
// rr_arbiter.sv — Round-Robin Arbiter (Icarus-compatible)
//
// Uses the classic "mask and double" technique:
//   - Mask out requests below the priority pointer
//   - If any masked request exists, grant the lowest one
//   - Otherwise, grant the lowest unmasked request
//============================================================================

module rr_arbiter #(
    parameter int N = 4
)(
    input  logic            clk,
    input  logic            rst_n,

    input  logic [N-1:0]    req,
    output logic [N-1:0]    grant,
    output logic            grant_valid,
    output logic [$clog2(N)-1:0] grant_idx
);

    localparam int IDX_W = $clog2(N) > 0 ? $clog2(N) : 1;

    // Priority pointer
    logic [IDX_W-1:0] priority_ptr;

    // Masked requests: zero out everything below priority_ptr
    logic [N-1:0] mask;
    logic [N-1:0] masked_req;
    logic [N-1:0] masked_grant;
    logic [N-1:0] unmasked_grant;
    logic         masked_any;

    // Build mask: mask[i] = 1 if i >= priority_ptr
    always_comb begin
        for (int i = 0; i < N; i++)
            mask[i] = (i[IDX_W-1:0] >= priority_ptr) ? 1'b1 : 1'b0;
    end

    assign masked_req = req & mask;

    // Priority encoder for masked requests (find lowest set bit)
    // Iterate top-down so last assignment wins = lowest index
    always_comb begin
        masked_grant = '0;
        for (int i = N-1; i >= 0; i--)
            if (masked_req[i]) masked_grant = (1 << i);
    end

    // Priority encoder for unmasked requests (fallback)
    always_comb begin
        unmasked_grant = '0;
        for (int i = N-1; i >= 0; i--)
            if (req[i]) unmasked_grant = (1 << i);
    end

    assign masked_any = |masked_req;

    // Select: prefer masked (above pointer), else unmasked (wrap around)
    assign grant = masked_any ? masked_grant : unmasked_grant;
    assign grant_valid = |req;

    // Encode grant index
    always_comb begin
        grant_idx = '0;
        for (int i = 0; i < N; i++)
            if (grant[i]) grant_idx = i[IDX_W-1:0];
    end

    // Update priority pointer
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            priority_ptr <= '0;
        else if (grant_valid)
            priority_ptr <= (grant_idx + 1) % N;
    end

endmodule