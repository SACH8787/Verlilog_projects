`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 09/29/2025 10:45:35 PM
// Design Name: 
// Module Name: tb
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


`timescale 1ns / 1ps
 
module tb();
 
/////global signal clk , rst
  
  reg clk;
  reg rst;
  
  reg [3:0] temp;
  
  //user logic goes here

initial begin
    clk = 0;
    rst = 0;
    #60;
    rst = 1;
end

/////// end your code 

  //1. Initialized Global Variable
  initial begin
    clk = 1'b0;
    rst = 1'b0;
  end
  ////2. Random signal for data/ control 
  
  initial begin
    rst = 1'b1;
    #30;
    rst = 1'b0;
  end
  
  
  initial begin
  temp = 4'b0100;
  #10;
  temp = 4'b1100;
  #10; 
  temp = 4'b0011;
  #10;  
  end
  
  
  ///////3. System Task at the start of simulation
  initial begin
    $dumpfile("dump.vcd");
    $dumpvars;
  end
  /////4. Analyzing Values of variable on COnsole
  initial begin
    $monitor("Temp : %0d at time : %0t", temp, $time);
  end
  
  ///5. Stop simulation by forcefully calling $finish
  initial begin
    #200;
    $finish();
  end
  
endmodule
