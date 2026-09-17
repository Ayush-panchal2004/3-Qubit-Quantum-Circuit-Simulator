// ============================================================
// sipp_v2_parallel.sv
// SIPP V2.1 — N Parallel MAC Units (Task 7 Research Upgrade)
// Author: Ayush Panchal | August 2026
// ============================================================
//
// TRUE PARALLEL ARCHITECTURE:
// This replaces the sequential 1-element/cycle MAC with N
// parallel multipliers that process N elements simultaneously.
//
// Pipeline stages per compute cycle:
//   Stage 0 (combinatorial): N parallel FP32 multipliers
//                            → N products in same clock cycle
//   Stage 1..STAGES (registered): N-input Adder Tree
//                            → reduces N products to 1 partial sum
//   Stage STAGES+1: Outer accumulator
//                            → sums all partial sums until row_done
//
// Throughput comparison (N=4 vs sequential):
//   Sequential: K cycles per row (K = number of non-zeros)
//   Parallel:   ceil(K/N) + log2(N) + 2 cycles per row
//   Speedup:    ~N / (1 + log2(N)/ceil(K/N))  → approaches N for large K
//
// Packing convention for mat_vals and x_elems:
//   mat_vals[k*32 +: 32] = the k-th matrix value  (k = 0..N-1)
//   x_elems [k*32 +: 32] = the k-th vector element (k = 0..N-1)
//
// IMPORTANT - Protocol:
//   1. Assert valid_i=1 each cycle with a FULL batch of N pairs.
//      Pad unused slots with mat_vals=0 (fp32_mul(0,x)=0, no effect).
//   2. After the LAST batch, de-assert valid_i, then pulse row_done=1
//      for exactly ONE cycle (valid_i must be 0 during row_done).
//   3. Wait for y_valid=1 before sending the next row's data.
// ============================================================

`timescale 1ns/1ps

import fp32_pkg::*;

module sipp_v2_parallel #(
    parameter N = 4       // Number of parallel MACs. Must be power of 2.
)(
    input  wire             clk,
    input  wire             rst_n,

    // N parallel (matrix value, vector element) input pairs
    input  wire [N*32-1:0]  mat_vals,  // N FP32 A[row][col] values packed
    input  wire [N*32-1:0]  x_elems,  // N FP32 x[col] values packed
    input  wire             valid_i,   // All N pairs are valid this cycle

    // Row control
    input  wire             row_done,  // Pulse after last valid batch

    // Output
    output logic [31:0]     y_out,     // FP32 dot product for this row
    output logic            y_valid    // y_out is valid this cycle
);

    localparam STAGES = $clog2(N);

    // ----------------------------------------------------------
    // Stage 0: N Parallel FP32 Multipliers (Combinatorial)
    // Produces N products in the same clock cycle as input
    // ----------------------------------------------------------
    wire [N*32-1:0] products_flat;

    genvar k;
    generate
        for (k = 0; k < N; k = k+1) begin : g_mul
            wire [31:0] va = mat_vals[k*32 +: 32];
            wire [31:0] vb = x_elems[k*32 +: 32];
            assign products_flat[k*32 +: 32] = fp32_pkg::fp32_mul(va, vb);
        end
    endgenerate

    // ----------------------------------------------------------
    // Stage 1..STAGES: N-input Pipelined Adder Tree
    // Reduces N products to 1 partial sum in log2(N) cycles
    // ----------------------------------------------------------
    wire [31:0] tree_out;
    wire        tree_valid;

    sipp_adder_tree #(.N(N)) u_tree (
        .clk     (clk),
        .rst_n   (rst_n),
        .valid_i (valid_i),
        .in_flat (products_flat),
        .sum_o   (tree_out),
        .valid_o (tree_valid)
    );

    // ----------------------------------------------------------
    // row_done delay shift register
    // Delays row_done by STAGES cycles to align with tree output.
    //
    // Timing (for STAGES=2):
    //   Last valid_i at cycle T-1, row_done at cycle T
    //   Last tree output appears at cycle T+STAGES-1
    //   Flush fires at cycle T+STAGES (after last tree capture)
    // ----------------------------------------------------------
    logic [STAGES-1:0] done_pipe;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) done_pipe <= {STAGES{1'b0}};
        else        done_pipe <= {done_pipe[STAGES-2:0], row_done};
    end

    wire flush = done_pipe[STAGES-1];  // Row flush signal, aligned with tree

    // ----------------------------------------------------------
    // Outer FP32 Accumulator
    // Accumulates partial sums from the adder tree each clock.
    // On flush: outputs the fully accumulated dot product and resets.
    //
    // Priority:
    //   flush + tree_valid: add last partial sum, then output & reset
    //   flush only:         output & reset (no more tree outputs)
    //   tree_valid only:    accumulate partial sum
    // ----------------------------------------------------------
    logic [31:0] accumulator;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            accumulator <= 32'h0;
            y_out       <= 32'h0;
            y_valid     <= 1'b0;
        end else begin
            y_valid <= 1'b0;  // Default: not valid

            if (flush && tree_valid) begin
                // Last partial sum arrives exactly when flush fires
                y_out       <= fp32_pkg::fp32_add(accumulator, tree_out);
                y_valid     <= 1'b1;
                accumulator <= 32'h0;
            end else if (flush) begin
                // Flush fires, no more tree outputs — output accumulated result
                y_out       <= accumulator;
                y_valid     <= 1'b1;
                accumulator <= 32'h0;
            end else if (tree_valid) begin
                // Intermediate partial sum — accumulate
                accumulator <= fp32_pkg::fp32_add(accumulator, tree_out);
            end
        end
    end

endmodule
