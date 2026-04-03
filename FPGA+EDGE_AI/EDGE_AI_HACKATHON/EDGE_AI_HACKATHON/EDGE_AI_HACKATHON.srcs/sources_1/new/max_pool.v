`timescale 1ns / 1ps
//==============================================================================
// max_pool.v  -  Global Max Pooling
//==============================================================================
module max_pool (
    input  wire               clk,
    input  wire               reset,
    input  wire signed [23:0] relu_in,
    output wire signed [23:0] pooled_out
);
    // Internal register to hold the maximum value
    reg signed [23:0] max_reg;

    always @(posedge clk) begin
        if (reset) begin
            max_reg <= 24'sd0;  // <-- Clear the internal register to 0
        end else begin
            // If the new input is bigger than our current max, update the max
            if (relu_in > max_reg) begin
                max_reg <= relu_in;
            end
        end
    end

    // Continuously assign the internal register to the output wire
    assign pooled_out = max_reg;

endmodule