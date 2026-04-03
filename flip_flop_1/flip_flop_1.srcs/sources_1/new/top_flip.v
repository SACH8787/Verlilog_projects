`timescale 1ns / 1ps

module top_flip (
    input clk_i,                // Clock
    input rstn_i,               // Reset (active low, assign to BTND)
    input [15:0] sw_i,          // Switches
    input btnu_i,               // BTNU (push/write)
    input btnc_i,               // BTNC (pop/read)
    output [15:0] led_o,        // LEDs
    output [7:0] disp_seg_o,    // 7-segment segments
    output [3:0] disp_an_o      // 7-segment digit enables
);

    // FIFO signals
    wire wr_en = btnu_i;        // Push on BTNU
    wire rd_en = btnc_i;        // Pop on BTNC
    wire [7:0] data_out;
    wire full, Empty;

    // FIFO instance
    flip_flop #(
        .DATA_WIDTH(8),
        .FIFO_WIDTH(16)
    ) fifo (
        .clk(clk_i),
        .reset(rstn_i),
        .wr_en(wr_en),
        .rd_en(rd_en),
        .Data_in(sw_i[7:0]),
        .Data_out(data_out),
        .full(full),
        .Empty(Empty)
    );

    // Assign LEDs
    assign led_o[7:0] = data_out;
    assign led_o[8]   = full;
    assign led_o[9]   = Empty;
    assign led_o[15:10] = 6'b0; // Unused

    // 7-segment display (show data_out)
    seg_mux smux(
        .clk(clk_i),
        .value(data_out),
        .seg(disp_seg_o),
        .an(disp_an_o)
    );

endmodule
