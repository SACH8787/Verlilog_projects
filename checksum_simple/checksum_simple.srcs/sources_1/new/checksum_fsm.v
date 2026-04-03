`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 18.07.2025 06:56:42
// Design Name: 
// Module Name: checksum_fsm
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


module checksum_fsm(
  input clk,
    input rst,
    input start,
    input fifo_empty,
    input [7:0] fifo_data,
    output reg rd_en,
    output reg done,
    output reg [7:0] checksum
);

    reg [1:0] state;
    parameter IDLE = 2'b00, READ = 2'b01, DONE = 2'b10;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            checksum <= 0;
            rd_en <= 0;
            done <= 0;
        end else begin
            case (state)
                IDLE: begin
                    rd_en <= 0;
                    done <= 0;
                    if (start) begin
                        checksum <= 0;
                        state <= READ;
                    end
                end

                READ: begin
                    if (!fifo_empty) begin
                        rd_en <= 1; // trigger one-cycle read
                        checksum <= checksum + fifo_data;
                    end else begin
                        rd_en <= 0;
                        state <= DONE;
                    end
                end

                DONE: begin
                    done <= 1;
                    state <= IDLE;
                end
            endcase
        end
    end


endmodule
