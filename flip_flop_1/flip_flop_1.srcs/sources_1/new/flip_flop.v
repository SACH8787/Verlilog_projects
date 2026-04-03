`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 25.06.2025 14:50:02
// Design Name: 
// Module Name: flip_flop
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


module flip_flop #(
parameter DATA_WIDTH=8,
parameter FIFO_WIDTH=16
    )(
    input clk,
    input reset,input wr_en,input rd_en, 
    input [DATA_WIDTH-1:0] Data_in,
    
    output reg[DATA_WIDTH-1:0] Data_out,
    output full,
    output Empty
    );
    
    //memory and pointers
    reg[DATA_WIDTH-1:0]memory [FIFO_WIDTH-1:0];
    reg[FIFO_WIDTH-1:0] wr_ptr=0;
    reg[FIFO_WIDTH-1:0] rd_ptr=0;
    reg[FIFO_WIDTH:0] count =0;
    
    //push logic
    always@(posedge clk) begin
      if(reset) begin
         wr_ptr<=0;
         end
      else if(wr_en && !full) begin
          memory[wr_ptr]=0;
          wr_ptr<=wr_ptr+1;
        end
      end
      
      //pop logic
      always @(posedge clk) begin
        if (reset) begin
            rd_ptr <= 0;
            Data_out <= 0;
          end
          else if (rd_en && !Empty) begin
            Data_out <= memory[rd_ptr];
            rd_ptr <= rd_ptr + 1;
        end
    end
    // count logic
    always@(posedge clk) begin
    if(reset) begin
       count<=0;
       end
     else begin
       case ({wr_en && !full, rd_en && !Empty})
          2'b10: count <= count + 1; // Write only
          2'b01: count <= count - 1; // Read only
          default: count <= count;   // no change or both
        endcase
    end
    end
    
      assign full = (count == FIFO_WIDTH);
    assign Empty = (count == 0);



       
       
          

endmodule
