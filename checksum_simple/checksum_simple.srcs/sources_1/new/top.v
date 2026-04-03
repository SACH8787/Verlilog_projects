`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 18.07.2025 06:58:30
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

module top(
    input clk,
    input rst,
    input wr_btn,     // Button to write data
    input done_btn,   // Button to start checksum
    input [7:0] sw_i, // Switch input data
    output [7:0] led  // Output checksum on LEDs
);

    wire [7:0] fifo_out;
    wire fifo_empty, fifo_full;

    wire wr_en = wr_btn;
    wire rd_en;
    wire done;
    wire [7:0] checksum;

    // FIFO instance
    simple_fifo fifo_inst(
        .clk(clk),
        .rst(rst),
        .wr_en(wr_en),
        .rd_en(rd_en),
        .data_in(sw_i),
        .data_out(fifo_out),
        .full(fifo_full),
        .empty(fifo_empty)
    );

    // FSM instance
    checksum_fsm fsm_inst(
        .clk(clk),
        .rst(rst),
        .start(done_btn),
        .fifo_empty(fifo_empty),
        .fifo_data(fifo_out),
        .rd_en(rd_en),
        .done(done),
        .checksum(checksum)
    );

    assign led = checksum;


endmodule
