`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 15.07.2025 01:10:46
// Design Name: 
// Module Name: led
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


module led(
    input clk,
    input reset,
    input [7:0] char_in,
    input write_en,
    output reg [3:0] lcd_data,
    output reg lcd_rs,
    output reg lcd_en
);

    reg [3:0] state = 0;
    reg [19:0] counter = 0;

    // Internal FSM
    parameter IDLE = 0, HIGH_NIB = 1, LOW_WAIT = 2, LOW_NIB = 3, DONE = 4;

    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            counter <= 0;
            lcd_en <= 0;
        end else begin
            counter <= counter + 1;

            case (state)
                IDLE: if (write_en) begin
                    lcd_rs <= 1;
                    lcd_data <= char_in[7:4];
                    lcd_en <= 1;
                    state <= HIGH_NIB;
                end

                HIGH_NIB: begin
                    lcd_en <= 0;
                    state <= LOW_WAIT;
                end

                LOW_WAIT: if (counter[17]) begin
                    lcd_data <= char_in[3:0];
                    lcd_en <= 1;
                    state <= LOW_NIB;
                end

                LOW_NIB: begin
                    lcd_en <= 0;
                    state <= DONE;
                end

                DONE: if (counter[19]) begin
                    state <= IDLE;
                    counter <= 0;
                end
            endcase
        end
    end
endmodule

