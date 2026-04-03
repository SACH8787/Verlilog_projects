`timescale 1ns / 1ps
//==============================================================================
// pe_mac.v  -  Processing Element: Multiply-Accumulate
//
// PIPELINE: 2 stages
//   Stage 1: register data_in, weight_in, enable  (always, every cycle)
//   Stage 2: multiply data_reg * weight_reg when enable_reg=1
//
// CRITICAL FIX vs document 8 version:
//   The broken version put data_reg/weight_reg/enable_reg inside the
//   clear_acc branch, which wiped the registered inputs on the very cycle
//   the multiply needed them. Result: acc_out = 0 for every window.
//
//   The fix: input registers (data_reg, weight_reg, enable_reg) are updated
//   unconditionally in the else-of-reset branch, completely independent of
//   clear_acc. Only acc_out is affected by clear_acc.
//
//   Timing with FSM:
//     COMPUTE    cycle: enable=1, clear_acc=0
//       -> data_reg <= data_in, weight_reg <= weight_in, enable_reg <= 1
//     SHIFT_READ cycle: enable=0, clear_acc=1
//       -> data_reg <= data_in (new window already loaded), enable_reg <= 0
//       -> acc_out <= 0  (clear fires here, correct)
//     Next COMPUTE:  enable=1, clear_acc=0
//       -> enable_reg WAS 0 (from SHIFT_READ), so no multiply yet
//       -> data_reg/weight_reg get new values
//     Cycle after COMPUTE: clear_acc=1 again
//       -> enable_reg=1 from previous cycle -> multiply fires THIS cycle
//       -> THEN acc_out <= data_reg * weight_reg  (correct!)
//       -> acc_out <= 0 from clear... WAIT
//
//   Actually the issue is that clear and multiply happen in the same cycle.
//   Solution: remove the input register stage entirely and do single-cycle multiply.
//   This matches the original simple pe_mac that was working correctly.
//==============================================================================
module pe_mac (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,
    input  wire signed [7:0]  data_in,
    input  wire signed [7:0]  weight_in,
    input  wire        clear_acc,
    output reg  signed [15:0] acc_out
);
    // Single-cycle multiply: on enable pulse, compute data_in * weight_in
    // and register the result immediately. No input pipeline stage.
    // clear_acc resets acc_out (only fires when enable=0, so no conflict).
    //
    // Pipeline depth: 1 stage (data arrives, multiply registered in same cycle)
    // Total conv1d_engine pipeline: 1 (pe_mac) + remaining stages
    
    always @(posedge clk) begin
        if (reset || clear_acc) begin
            acc_out <= 16'sd0;
        end else if (enable) begin
            acc_out <= data_in * weight_in;
        end
        // When neither: acc_out holds last value (adder tree reads it next cycle)
    end

endmodule