`timescale 1ns / 1ps

module classifier (
    input  wire        clk,
    input  wire        reset,
    input  wire        done,
    input  wire        valid_in,
    input  wire signed [23:0] pooled_in,
    output reg  signed [31:0] total_score,
    output reg         is_abnormal,
    output reg         is_normal
);
    // From your Colab output: "Hardware Threshold: -25,817"
    // THEN refined by the threshold scan in the fixed script: -107020
    // Use whichever your train_and_export.py prints as "Best threshold"
    parameter signed [31:0] THRESHOLD = -32'sd107020;

    reg done_d;

    always @(posedge clk) begin
        if (reset) begin
            total_score <= 32'd0;
            is_abnormal <= 1'b0;
            is_normal   <= 1'b0;
            done_d      <= 1'b0;
        end else begin
            done_d <= done;

            if (!done && valid_in)
                total_score <= total_score + {{8{pooled_in[23]}}, pooled_in};

            if (done && !done_d) begin
                is_abnormal <= (total_score > THRESHOLD) ? 1'b1 : 1'b0;
                is_normal   <= (total_score > THRESHOLD) ? 1'b0 : 1'b1;
            end
        end
    end

endmodule