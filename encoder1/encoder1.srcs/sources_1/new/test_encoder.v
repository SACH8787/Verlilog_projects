`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 17.06.2025 13:41:22
// Design Name: 
// Module Name: test_encoder
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


module test_encoder;
reg [2:0] D;
 wire [7:0] y;

  encoder3_8 uut (.D(D), .y(y));

  initial begin
    $display("---- Truth Table of 3-to-8 Decoder ----");
    $display("D   | y");
    $monitor("%b | %b", D, y);

    D = 3'b000; #5;
    D = 3'b001; #5;
    D = 3'b010; #5;
    D = 3'b011; #5;
    D = 3'b100; #5;
    D = 3'b101; #5;
    D = 3'b110; #5;
    D = 3'b111; #5;

    $finish;
  end
endmodule
