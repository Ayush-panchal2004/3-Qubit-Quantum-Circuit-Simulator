// ============================================================
// sipp_fp32_mac.sv
// SIPP V2.0 — IEEE 754 FP32 Multiply-Accumulate Unit
// Author: Ayush Panchal | August 2026
// ============================================================
// Replaces: sipp_mac_unit.sv (INT32 fixed-point)
// Upgrade:  Full IEEE 754 single-precision FP32 arithmetic
//
// Operation each clock cycle when valid_i=1:
//   product     = fp32_mul(value_i, x_elem_i)
//   accumulator = fp32_add(accumulator, product)
//
// When row_done_i=1:
//   result_o    = accumulator   (FP32 dot product for this row)
//   result_we   = 1             (write to output SRAM)
//   accumulator = 0.0           (reset for next row)
//
// Latency: 1 cycle (combinatorial multiply + add, then register)
// ============================================================

`timescale 1ns/1ps

// Import the shared FP32 math package
import fp32_pkg::fp32_mul;
import fp32_pkg::fp32_add;

module sipp_fp32_mac #(
    parameter ADDR_W = 9
)(
    input  wire        clk,
    input  wire        rst_n,

    // Data inputs (IEEE 754 FP32)
    input  wire [31:0] value_i,    // Matrix non-zero element A[row][col]
    input  wire [31:0] x_elem_i,   // Vector element x[col]
    input  wire        valid_i,    // Data valid strobe
    input  wire        row_done_i, // End-of-row signal from Row Controller

    // Result output (IEEE 754 FP32)
    output reg  [31:0] result_o,   // Accumulated dot product for this row
    output reg         result_we   // Write enable to output SRAM
);

    // ---------------------------------------------------------
    // Accumulator register (FP32)
    // ---------------------------------------------------------
    reg [31:0] accumulator;

    // Combinatorial product (computed every cycle, used when valid)
    wire [31:0] product = fp32_pkg::fp32_mul(value_i, x_elem_i);

    // ---------------------------------------------------------
    // MAC State Machine
    // ---------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            accumulator <= 32'h0000_0000;  // 0.0 in FP32
            result_o    <= 32'h0000_0000;
            result_we   <= 1'b0;
        end else begin
            result_we <= 1'b0;  // default: no write

            if (row_done_i) begin
                // Row complete: output accumulated sum, reset for next row
                result_o    <= accumulator;
                result_we   <= 1'b1;
                accumulator <= 32'h0000_0000;

                // synthesis translate_off
                $display("[FP32 MAC %m] row_done: result=32'h%h", accumulator);
                // synthesis translate_on

            end else if (valid_i) begin
                // New element: multiply and accumulate
                accumulator <= fp32_pkg::fp32_add(accumulator, product);

                // synthesis translate_off
                $display("[FP32 MAC %m] valid: value=%h x=%h product=%h new_acc=%h",
                         value_i, x_elem_i, product,
                         fp32_pkg::fp32_add(accumulator, product));
                // synthesis translate_on
            end
        end
    end

endmodule
