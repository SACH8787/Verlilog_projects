`timescale 1ns / 1ps

module rom_memory #(
    parameter FILE_NAME = "test_ecg_abnormal.mem", 
    parameter MEM_DEPTH = 128
)(
    input wire clk,
    input wire [7:0] address,
    output reg signed [7:0] data_out
);

    reg signed [7:0] mem_array [0:MEM_DEPTH-1];

    initial begin
        $readmemh(FILE_NAME, mem_array);
    end

    always @(posedge clk) begin
        data_out <= mem_array[address];
    end

endmodule