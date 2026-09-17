// ============================================================
// fp32_pkg.sv
// SIPP V2.0 — IEEE 754 FP32 Shared Math Functions
// Author: Ayush Panchal | August 2026
// ============================================================
// Contains two automatic functions used by both the FP32 MAC
// unit and the Adder Tree:
//   fp32_mul(a, b) → IEEE 754 single-precision multiply
//   fp32_add(a, b) → IEEE 754 single-precision add
//
// Scope: Normal numbers + zero only (NaN/Inf not needed for
//        physics simulation with bounded inputs)
// ============================================================

package fp32_pkg;

    // --------------------------------------------------------
    // FP32 Multiply: returns a * b in IEEE 754 single precision
    // Pipeline equivalent: 3 combinatorial stages
    // --------------------------------------------------------
    function automatic [31:0] fp32_mul;
        input [31:0] a, b;

        reg        sign_a, sign_b, sign_p;
        reg [7:0]  exp_a,  exp_b,  exp_out;
        reg [9:0]  exp_p;
        reg [23:0] man_a,  man_b;
        reg [47:0] man_p;
        reg [22:0] man_out;

        begin
            // --- Unpack ---
            sign_a = a[31];
            sign_b = b[31];
            exp_a  = a[30:23];
            exp_b  = b[30:23];

            // --- Zero check (exp=0 → zero for normal numbers) ---
            if (exp_a == 8'h00 || exp_b == 8'h00) begin
                fp32_mul = 32'h0000_0000;
            end else begin
                // Add implicit leading 1 to mantissa
                man_a = {1'b1, a[22:0]};
                man_b = {1'b1, b[22:0]};

                // --- Sign ---
                sign_p = sign_a ^ sign_b;

                // --- Mantissa product: 24x24 → 48 bits ---
                man_p = man_a * man_b;

                // --- Exponent: ea + eb − 127 (remove one bias) ---
                exp_p = {2'b00, exp_a} + {2'b00, exp_b} - 10'd127;

                // --- Normalize ---
                // Product is either 1x.xxx (bit47=1) or 01.xxx (bit47=0)
                if (man_p[47]) begin
                    // Overflow by 1 bit: take [46:24], increment exp
                    man_out = man_p[46:24];
                    exp_out = exp_p[7:0] + 8'd1;
                end else begin
                    // Already normalized: take [45:23]
                    man_out = man_p[45:23];
                    exp_out = exp_p[7:0];
                end

                fp32_mul = {sign_p, exp_out, man_out};
            end
        end
    endfunction

    // --------------------------------------------------------
    // FP32 Add: returns a + b in IEEE 754 single precision
    // Handles: same-sign add, different-sign subtract, zero
    // --------------------------------------------------------
    function automatic [31:0] fp32_add;
        input [31:0] a, b;

        reg        sign_a, sign_b, sign_out;
        reg [7:0]  exp_a,  exp_b,  e_out;
        reg [7:0]  exp_diff;
        reg [24:0] man_a_ext, man_b_ext;
        reg [24:0] man_large, man_small, man_sum;
        reg [22:0] man_out;
        integer    k;

        begin
            // --- Zero pass-through ---
            if (a == 32'h0) begin
                fp32_add = b;
            end else if (b == 32'h0) begin
                fp32_add = a;
            end else begin
                sign_a    = a[31];
                sign_b    = b[31];
                exp_a     = a[30:23];
                exp_b     = b[30:23];
                // Extend mantissa to 25 bits: {guard, implicit_1, frac[22:0]}
                man_a_ext = {1'b0, 1'b1, a[22:0]};
                man_b_ext = {1'b0, 1'b1, b[22:0]};

                // --- Align to the larger exponent ---
                if (exp_a >= exp_b) begin
                    e_out     = exp_a;
                    exp_diff  = exp_a - exp_b;
                    man_large = man_a_ext;
                    man_small = man_b_ext >> exp_diff;
                    sign_out  = sign_a;
                end else begin
                    e_out     = exp_b;
                    exp_diff  = exp_b - exp_a;
                    man_large = man_b_ext;
                    man_small = man_a_ext >> exp_diff;
                    sign_out  = sign_b;
                end

                // --- Add or subtract mantissas ---
                if (sign_a == sign_b) begin
                    // Same sign → add
                    man_sum  = man_large + man_small;
                    sign_out = sign_a;
                end else begin
                    // Different signs → subtract
                    if (man_large >= man_small) begin
                        man_sum = man_large - man_small;
                        // sign_out already correct (larger magnitude)
                    end else begin
                        man_sum  = man_small - man_large;
                        sign_out = ~sign_out;
                    end
                end

                // --- Normalize ---
                if (man_sum == 25'h0) begin
                    // Exact cancellation → zero
                    fp32_add = 32'h0;
                end else if (man_sum[24]) begin
                    // Overflow: shift right by 1, increment exponent
                    man_out  = man_sum[23:1];
                    e_out    = e_out + 8'd1;
                    fp32_add = {sign_out, e_out, man_out};
                end else begin
                    // Normalize: left-shift until bit 23 is 1
                    for (k = 0; k < 23; k = k + 1) begin
                        if (!man_sum[23] && (e_out > 8'd0)) begin
                            man_sum = man_sum << 1;
                            e_out   = e_out - 8'd1;
                        end
                    end
                    man_out  = man_sum[22:0];
                    fp32_add = {sign_out, e_out, man_out};
                end
            end
        end
    endfunction

endpackage
