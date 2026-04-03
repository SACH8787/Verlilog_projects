`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 14.07.2025 12:48:07
// Design Name: 
// Module Name: top
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

module top (
    input clk,
    input reset,
    output [3:0] lcd_data,
    output lcd_rs,
    output lcd_en
);

    // 25MHz Clock Divider
    reg [1:0] clk_div = 0;
    always @(posedge clk)
        clk_div <= clk_div + 1;
    wire slow_clk = clk_div[1];

    // Signal Index
    reg [7:0] index = 0;
    always @(posedge slow_clk)
        if (reset)
            index <= 0;
        else
            index <= index + 1;

    // Input: Sawtooth Wave
    wire [7:0] input_sample = index;
    wire [9:0] filtered_sample;

    // Convolution
    convolution conv (
        .clk(slow_clk),
        .reset(reset),
        .data_in(input_sample),
        .data_out(filtered_sample)
    );

    // Convert to ASCII
    wire [7:0] in_h, in_t, in_o;
    wire [7:0] out_h, out_t, out_o;

    ascii conv_in  (.number(input_sample), .hundreds(in_h), .tens(in_t), .ones(in_o));
    ascii conv_out (.number(filtered_sample), .hundreds(out_h), .tens(out_t), .ones(out_o));

    // LCD Character FSM
    reg [7:0] char;
    reg wr_en = 0;
    reg [4:0] char_idx = 0;
    reg [19:0] delay = 0;

    always @(posedge slow_clk) begin
        delay <= delay + 1;
        if (delay == 20'd800_000) begin
            wr_en <= 1;
            delay <= 0;
            case (char_idx)
                0:  char <= "I";
                1:  char <= "n";
                2:  char <= ":";
                3:  char <= in_h;
                4:  char <= in_t;
                5:  char <= in_o;
                6:  char <= " ";
                7:  char <= "O";
                8:  char <= "u";
                9:  char <= "t";
                10: char <= ":";
                11: char <= out_h;
                12: char <= out_t;
                13: char <= out_o;
                14: char <= " ";
                15: char <= " ";
            endcase
            char_idx <= (char_idx == 15) ? 0 : char_idx + 1;
        end else
            wr_en <= 0;
    end

    // LCD Controller
    led lcd (
        .clk(clk),
        .reset(reset),
        .char_in(char),
        .write_en(wr_en),
        .lcd_data(lcd_data),
        .lcd_rs(lcd_rs),
        .lcd_en(lcd_en)
    );

endmodule

