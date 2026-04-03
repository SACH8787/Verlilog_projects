`timescale 1ns / 1ps

module bin2seg(
    input [3:0] bin,
    output reg [7:0] seg
);
    always @(*) begin
        case(bin)
            4'h0: seg = 8'b11000000; // 0
            4'h1: seg = 8'b11111001; // 1
            4'h2: seg = 8'b10100100; // 2
            4'h3: seg = 8'b10110000; // 3
            4'h4: seg = 8'b10011001; // 4
            4'h5: seg = 8'b10010010; // 5
            4'h6: seg = 8'b10000010; // 6
            4'h7: seg = 8'b11111000; // 7
            4'h8: seg = 8'b10000000; // 8
            4'h9: seg = 8'b10010000; // 9
            4'hA: seg = 8'b10001000; // A
            4'hB: seg = 8'b10000011; // B
            4'hC: seg = 8'b11000110; // C
            4'hD: seg = 8'b10100001; // D
            4'hE: seg = 8'b10000110; // E
            4'hF: seg = 8'b10001110; // F
            default: seg = 8'b11111111; // off
        endcase
    end
endmodule
