`timescale 1ns / 1ps

module seg_mux(
    input clk,
    input [7:0] value,
    output reg [7:0] seg,
    output reg [3:0] an
);
    reg sel = 0;
    wire [3:0] nibble = sel ? value[7:4] : value[3:0];
    wire [7:0] seg_out;
    
    bin2seg b2s(.bin(nibble), .seg(seg_out));
    
    always @(posedge clk) begin
        sel <= ~sel;
    end
    
    always @(*) begin
        seg = seg_out;
        // Enable only digit 0 or 1 (active low)
        an = ~(1 << sel); // If sel=0: an=4'b1110, if sel=1: an=4'b1101
    end
endmodule
