`timescale 1ns / 1ps

module relu (
    input wire signed [23:0] data_in,
    output wire signed [23:0] data_out
);
    assign data_out = (data_in < 0) ? 24'd0 : data_in;
endmodule