`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 15.07.2025 01:10:07
// Design Name: 
// Module Name: ascii
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


module ascii(
    input [9:0] number,
    output [7:0] hundreds,
    output [7:0] tens,
    output [7:0] ones
);

    reg [9:0] temp;
    reg [3:0] h, t, o;

    always @(*) begin
        temp = number;
        h = temp / 100;
        temp = temp % 100;
        t = temp / 10;
        o = temp % 10;
    end

    assign hundreds = h + 8'd48;
    assign tens     = t + 8'd48;
    assign ones     = o + 8'd48;
endmodule

