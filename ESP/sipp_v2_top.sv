// ============================================================
// sipp_v2_top.sv
// SIPP V2.1 — Top-Level SpMV Integration
// Author: Ayush Panchal | August 2026
// ============================================================
//
// Integrates sipp_fp32_mac and sipp_adder_tree into a
// complete FP32 Sparse Matrix-Vector Multiply (SpMV) engine.
//
// Data Flow:
//   mat_val x x_elem → [FP32 MAC] → accumulates per-row dot product
//                                  ↓  (on row_done)
//                        [Pipelined Adder Tree] → y_out
//
// Interface: Streaming — caller feeds one non-zero element per cycle.
// The adder tree is in the output pipeline. For N=4, it adds a
// log2(4)=2 cycle latency. In Phase 4, N MACs will feed the tree
// with N products per cycle for full parallel acceleration.
//
// Latency (from last row_done to y_valid): log2(N) + 1 cycles
// ============================================================

`timescale 1ns/1ps

module sipp_v2_top #(
    parameter N = 4    // Adder Tree width. Must be power of 2.
)(
    input  wire        clk,
    input  wire        rst_n,

    // --- Streaming Sparse Matrix Input ---
    // Feed one non-zero element (and its x vector pair) each cycle.
    // After the LAST element of a row, pulse row_done for one cycle
    // with valid_i = 0.
    input  wire [31:0] mat_val,    // A[row][col] — non-zero matrix value (FP32)
    input  wire [31:0] x_elem,     // x[col]      — corresponding vector element (FP32)
    input  wire        valid_i,    // mat_val and x_elem are valid this cycle
    input  wire        row_done,   // All elements of the current row have been fed

    // --- Row Result Output ---
    // y_valid pulses high log2(N)+1 cycles after row_done.
    // Capture y_out on the same cycle as y_valid.
    output wire [31:0] y_out,      // FP32 dot product: sum(A[row][*] * x[*])
    output wire        y_valid     // y_out is valid this cycle
);

    // ----------------------------------------------------------
    // Stage 1: FP32 MAC Unit
    // Accumulates product pairs for the current row.
    // On row_done, outputs the accumulated dot product (mac_result)
    // and asserts mac_we for exactly one cycle.
    // ----------------------------------------------------------
    wire [31:0] mac_result;
    wire        mac_we;

    sipp_fp32_mac #(.ADDR_W(9)) u_mac (
        .clk        (clk),
        .rst_n      (rst_n),
        .value_i    (mat_val),
        .x_elem_i   (x_elem),
        .valid_i    (valid_i),
        .row_done_i (row_done),
        .result_o   (mac_result),
        .result_we  (mac_we)
    );

    // ----------------------------------------------------------
    // Stage 2: Pipelined FP32 Adder Tree
    //
    // Current integration (Phase 3):
    //   The MAC unit produces one result per row. We place it into
    //   in[0] of the tree, with in[1..N-1] = 0.0. Because our
    //   fp32_add handles zero pass-through (0+x = x), the tree
    //   passes the result correctly through all stages.
    //
    //   This wiring adds log2(N) pipeline cycles after mac_we,
    //   demonstrating the full integrated pipeline path.
    //
    // Phase 4 upgrade:
    //   Replace with N parallel MAC multipliers, each producing
    //   one product per cycle → all N fed to the tree simultaneously
    //   → true O(log2 N) parallel accumulation.
    // ----------------------------------------------------------
    wire [N*32-1:0] tree_in_flat;

    // Pack: in[0] = mac_result, in[1..N-1] = 0.0
    assign tree_in_flat = {{(N-1)*32{1'b0}}, mac_result};

    sipp_adder_tree #(.N(N)) u_tree (
        .clk     (clk),
        .rst_n   (rst_n),
        .valid_i (mac_we),
        .in_flat (tree_in_flat),
        .sum_o   (y_out),
        .valid_o (y_valid)
    );

endmodule
