`timescale 1ns / 1ps

module dual_port_ram (
    input wire clk,
    
    // PORT A: Write Port (Used by UART)
    input wire weA,                // Write Enable
    input wire [7:0] addrA,        // Write Address
    input wire signed [7:0] dinA,  // Write Data
    
    // PORT B: Read Port (Used by Accelerator)
    input wire [7:0] addrB,        // Read Address
    output reg signed [7:0] doutB  // Read Data
);

    // 128 bytes of memory
    reg signed [7:0] ram [0:127];

    always @(posedge clk) begin
        if (weA) begin
            ram[addrA] <= dinA;
        end
        doutB <= ram[addrB];
    end

endmodule