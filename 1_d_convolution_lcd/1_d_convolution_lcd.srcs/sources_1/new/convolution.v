`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 15.07.2025 01:09:09
// Design Name: 
// Module Name: convolution
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module convolution(

    input clk,
    input reset,
    input [7:0] data_in,
    output reg [9:0] data_out
);

    reg [7:0] kernel[0:2];
    initial begin
        kernel[0] = 8'd1;
        kernel[1] = 8'd2;
        kernel[2] = 8'd1;
    end

    reg [7:0] shift_reg[0:2];
    integer i;

    always @(posedge clk) begin
        if (reset)
            for (i = 0; i < 3; i = i + 1)
                shift_reg[i] <= 0;
        else begin
            shift_reg[0] <= data_in;
            shift_reg[1] <= shift_reg[0];
            shift_reg[2] <= shift_reg[1];
        end
    end

    always @(posedge clk) begin
        if (reset)
            data_out <= 0;
        else
            data_out <= (shift_reg[0]*kernel[0] + shift_reg[1]*kernel[1] + shift_reg[2]*kernel[2]) >> 2;
    end
endmodule

