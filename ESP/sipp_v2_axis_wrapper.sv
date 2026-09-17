// ============================================================
// sipp_v2_axis_wrapper.sv
// SIPP V2.1 — AXI4-Stream Wrapper for Hardware Deployment
// Author: Ayush Panchal | August 2026
// ============================================================
// Wraps the raw SIPP V2 core in industry-standard AXI4-Stream
// interfaces. This allows seamless integration with Xilinx Zynq/MicroBlaze
// processors via Direct Memory Access (DMA) for high-speed testing.
// ============================================================

`timescale 1ns/1ps

module sipp_v2_axis_wrapper #(
    parameter N = 4
)(
    input  wire                   clk,
    input  wire                   rst_n,

    // AXI4-Stream Slave Interface (Data IN from DMA)
    // TDATA: Upper half = x_elems, Lower half = mat_vals
    input  wire [N*64-1:0]        s_axis_tdata,
    input  wire                   s_axis_tvalid,
    input  wire                   s_axis_tlast,  // End of matrix row
    output logic                  s_axis_tready,

    // AXI4-Stream Master Interface (Data OUT to DMA)
    output wire [31:0]            m_axis_tdata,
    output wire                   m_axis_tvalid,
    output wire                   m_axis_tlast,  // Always 1 for dot product
    input  wire                   m_axis_tready
);

    // --------------------------------------------------------
    // FSM to handle the row_done protocol mismatch
    // AXI streams tlast WITH the last data word.
    // SIPP core expects row_done the cycle AFTER the last data word.
    // --------------------------------------------------------
    typedef enum logic {
        STATE_STREAMING,
        STATE_FLUSH
    } state_t;
    
    state_t state;

    logic core_valid_i;
    logic core_row_done;
    
    wire [N*32-1:0] mat_vals = s_axis_tdata[N*32-1 : 0];
    wire [N*32-1:0] x_elems  = s_axis_tdata[N*64-1 : N*32];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= STATE_STREAMING;
        end else begin
            case (state)
                STATE_STREAMING: begin
                    if (s_axis_tvalid && s_axis_tready && s_axis_tlast) begin
                        state <= STATE_FLUSH; // Move to flush cycle
                    end
                end
                STATE_FLUSH: begin
                    // One cycle delay to issue row_done, then return to streaming
                    state <= STATE_STREAMING;
                end
            endcase
        end
    end

    // Combinational logic for core controls and AXI ready
    always_comb begin
        core_valid_i  = 1'b0;
        core_row_done = 1'b0;
        s_axis_tready = 1'b0;

        if (state == STATE_STREAMING) begin
            // We can accept data if the downstream master is ready
            s_axis_tready = m_axis_tready;
            core_valid_i  = s_axis_tvalid && s_axis_tready;
        end else if (state == STATE_FLUSH) begin
            // Issue row_done while valid_i is 0
            core_row_done = 1'b1;
            s_axis_tready = 1'b0; // Block new data during flush
        end
    end

    // --------------------------------------------------------
    // SIPP Core Instantiation
    // --------------------------------------------------------
    sipp_v2_parallel #(
        .N(N)
    ) u_core (
        .clk        (clk),
        .rst_n      (rst_n),
        .mat_vals   (mat_vals),
        .x_elems    (x_elems),
        .valid_i    (core_valid_i),
        .row_done   (core_row_done),
        .y_out      (m_axis_tdata),
        .y_valid    (m_axis_tvalid)
    );

    // Each output represents a complete dot product for a row
    assign m_axis_tlast = m_axis_tvalid;

endmodule
