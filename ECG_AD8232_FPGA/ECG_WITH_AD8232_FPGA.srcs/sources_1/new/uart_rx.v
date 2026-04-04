`timescale 1ns / 1ps

module uart_rx #(
    parameter CLKS_PER_BIT = 868 // 100MHz / 115200 Baud
)(
    input wire clk,
    input wire rx,
    output reg [7:0] rx_data,
    output reg rx_done
);

    localparam IDLE = 3'd0, START = 3'd1, DATA = 3'd2, STOP = 3'd3;
    reg [2:0] state = IDLE;
    
    reg [9:0] clk_count = 0;
    reg [2:0] bit_index = 0;

    always @(posedge clk) begin
        case (state)
            IDLE: begin
                rx_done <= 1'b0;
                clk_count <= 0;
                bit_index <= 0;
                if (rx == 1'b0) // Start bit detected
                    state <= START;
                else
                    state <= IDLE;
            end
            
            START: begin
                if (clk_count == (CLKS_PER_BIT-1)/2) begin
                    if (rx == 1'b0) begin
                        clk_count <= 0;
                        state <= DATA;
                    end else
                        state <= IDLE;
                end else begin
                    clk_count <= clk_count + 1;
                    state <= START;
                end
            end
            
            DATA: begin
                if (clk_count < CLKS_PER_BIT-1) begin
                    clk_count <= clk_count + 1;
                    state <= DATA;
                end else begin
                    clk_count <= 0;
                    rx_data[bit_index] <= rx;
                    if (bit_index < 7) begin
                        bit_index <= bit_index + 1;
                        state <= DATA;
                    end else begin
                        bit_index <= 0;
                        state <= STOP;
                    end
                end
            end
            
            STOP: begin
                if (clk_count < CLKS_PER_BIT-1) begin
                    clk_count <= clk_count + 1;
                    state <= STOP;
                end else begin
                    rx_done <= 1'b1;
                    clk_count <= 0;
                    state <= IDLE;
                end
            end
            
            default: state <= IDLE;
        endcase
    end
endmodule