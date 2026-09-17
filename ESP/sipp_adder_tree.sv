// ============================================================
// sipp_adder_tree.sv  —  Parametric N-Input Pipelined FP32 Adder Tree
// SIPP V2.1 (Research Edition)
// Author: Ayush Panchal | August 2026
// ============================================================
//
// RESEARCH UPGRADE from V2.0 (hardcoded 4-input):
// This version is fully parametric — set N at instantiation:
//
//   sipp_adder_tree #(.N(4))  dut  → 2 stages, log2(4)=2  cycle latency
//   sipp_adder_tree #(.N(8))  dut  → 3 stages, log2(8)=3  cycle latency
//   sipp_adder_tree #(.N(16)) dut  → 4 stages, log2(16)=4 cycle latency
//   sipp_adder_tree #(.N(32)) dut  → 5 stages, log2(32)=5 cycle latency
//
// Architecture (N=8 example):
//
//   in[0] in[1] | in[2] in[3] | in[4] in[5] | in[6] in[7]   ← from in_flat
//       \   /         \   /         \   /         \   /
//     s0[0]          s0[1]         s0[2]          s0[3]  ← Stage 0 (reg, 4 nodes)
//         \           /                \           /
//           s1[0]                        s1[1]          ← Stage 1 (reg, 2 nodes)
//               \                         /
//                          s2[0]                        ← Stage 2 (reg, 1 node) → sum_o
//
// Port Note: Inputs are packed into a single wide bus for Icarus compatibility:
//   in_flat[31:0]   = in[0]  (first element)
//   in_flat[63:32]  = in[1]
//   ...
//   in_flat[N*32-1:(N-1)*32] = in[N-1] (last element)
//
// Latency:    $clog2(N) clock cycles  (auto-computed at compile time)
// Throughput: 1 result per clock cycle (fully pipelined after startup)
// ============================================================

`timescale 1ns/1ps

import fp32_pkg::*;

module sipp_adder_tree #(
    parameter N = 4          // Number of FP32 inputs. MUST be a power of 2.
)(
    input  wire             clk,
    input  wire             rst_n,
    input  wire             valid_i,

    // All N FP32 inputs packed into one wide bus
    // Packing: in_flat = { in[N-1], ..., in[1], in[0] }
    // Access:  in[k]   = in_flat[ k*32 +: 32 ]
    input  wire [N*32-1:0]  in_flat,

    // Reduced FP32 sum of all N inputs
    output logic [31:0]     sum_o,
    output logic            valid_o
);

    // ----------------------------------------------------------
    // Auto-compute pipeline depth from N at compile time
    // $clog2(4)=2, $clog2(8)=3, $clog2(16)=4
    // ----------------------------------------------------------
    localparam STAGES = $clog2(N);

    // ----------------------------------------------------------
    // Pipeline register array: stages[s][j]
    //   s = pipeline stage index (0 to STAGES-1)
    //   j = node index within that stage
    //
    //   stages[0][0..N/2-1]   = Stage 1 outputs  (N/2 values, registered)
    //   stages[1][0..N/4-1]   = Stage 2 outputs  (N/4 values, registered)
    //   stages[STAGES-1][0]   = Final sum         (1 value,   registered)
    //
    // IMPORTANT: Only driven by always blocks — no assign drivers.
    // Stage 0 of the tree reads directly from in_flat (not stored here).
    // ----------------------------------------------------------
    logic [31:0] stages [0:STAGES-1][0:N-1];

    // ----------------------------------------------------------
    // Valid-bit shift register
    // Propagates valid_i through STAGES clock cycles
    // vld_pipe[0]        = valid after stage 1
    // vld_pipe[STAGES-1] = valid at output
    // ----------------------------------------------------------
    logic [STAGES-1:0] vld_pipe;

    // NOTE: When STAGES=1 (N=2), the expression vld_pipe[STAGES-2:0]
    // evaluates to vld_pipe[-1:0] which is an illegal negative index.
    // The generate guard below handles this edge case safely.
    generate
        if (STAGES == 1) begin : g_vld_s1
            // Single-stage: output valid one cycle after input
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) vld_pipe <= 1'b0;
                else        vld_pipe <= valid_i;
            end
        end else begin : g_vld_sn
            // Multi-stage (N>=4): shift valid through pipeline depth
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) vld_pipe <= {STAGES{1'b0}};
                else        vld_pipe <= {vld_pipe[STAGES-2:0], valid_i};
            end
        end
    endgenerate

    // ----------------------------------------------------------
    // Binary Reduction Tree — Generated at compile time
    //
    // For each stage s (0 to STAGES-1):
    //   s=0: Read from in_flat, write to stages[0]
    //   s>0: Read from stages[s-1], write to stages[s]
    //   Each stage has N >> (s+1) active adder nodes
    // ----------------------------------------------------------
    genvar s, j;
    generate

        // === Stage 0: Inputs come from in_flat (packed bus) ===
        for (j = 0; j < N/2; j = j+1) begin : g_stage0
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    stages[0][j] <= 32'h0000_0000;
                end else begin
                    stages[0][j] <= fp32_pkg::fp32_add(
                        in_flat[(2*j  )*32 +: 32],   // Left child  in[2j]
                        in_flat[(2*j+1)*32 +: 32]    // Right child in[2j+1]
                    );
                    // synthesis translate_off
                    if (valid_i)
                        $display("[Tree S1] adder=%0d : %h + %h = %h",
                            j,
                            in_flat[(2*j  )*32 +: 32],
                            in_flat[(2*j+1)*32 +: 32],
                            fp32_pkg::fp32_add(
                                in_flat[(2*j  )*32 +: 32],
                                in_flat[(2*j+1)*32 +: 32]));
                    // synthesis translate_on
                end
            end
        end

        // === Stages 1..STAGES-1: Inputs come from previous stage ===
        for (s = 1; s < STAGES; s = s+1) begin : g_stage_n
            for (j = 0; j < (N >> (s+1)); j = j+1) begin : g_node
                always @(posedge clk or negedge rst_n) begin
                    if (!rst_n) begin
                        stages[s][j] <= 32'h0000_0000;
                    end else begin
                        stages[s][j] <= fp32_pkg::fp32_add(
                            stages[s-1][2*j],      // Left child
                            stages[s-1][2*j+1]     // Right child
                        );
                        // synthesis translate_off
                        if (vld_pipe[s-1])
                            $display("[Tree S%0d] adder=%0d : %h + %h = %h",
                                s+1, j,
                                stages[s-1][2*j],
                                stages[s-1][2*j+1],
                                fp32_pkg::fp32_add(
                                    stages[s-1][2*j],
                                    stages[s-1][2*j+1]));
                        // synthesis translate_on
                    end
                end
            end
        end

    endgenerate

    // ----------------------------------------------------------
    // Outputs: Final node of the binary tree
    // ----------------------------------------------------------
    assign sum_o   = stages[STAGES-1][0];
    assign valid_o = vld_pipe[STAGES-1];

endmodule
