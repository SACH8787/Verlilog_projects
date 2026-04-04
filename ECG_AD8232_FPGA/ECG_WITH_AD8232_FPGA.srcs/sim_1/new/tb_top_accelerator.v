`timescale 1ns / 1ps

module tb_top_accelerator;

    // -------------------------------------------------------
    // 1. Declare Testbench Signals
    // -------------------------------------------------------
    reg clk;
    reg reset;
    reg start;

    // Signals for the external ECG memory interface
    wire [7:0] ecg_read_addr;
    reg signed [7:0] ecg_read_data;

    wire done;
    wire signed [23:0] final_mac_result;
    wire [119:0] debug_window;
    wire signed [23:0] relu_result;
    wire signed [23:0] pooled_result;
    wire signed [31:0] total_score;
    wire is_abnormal;
    wire is_normal;

    // -------------------------------------------------------
    // 2. Simulated External ECG Memory
    // -------------------------------------------------------
    // We create a memory array right here in the TB to feed the accelerator
    reg signed [7:0] testbench_ecg_mem [0:255];

    // Read logic to mimic a standard synchronous ROM/RAM
    always @(posedge clk) begin
        ecg_read_data <= testbench_ecg_mem[ecg_read_addr];
    end

    // -------------------------------------------------------
    // 3. Instantiate the Top-Level Unit Under Test (UUT)
    // -------------------------------------------------------
    top_accelerator uut (
        .clk(clk),
        .reset(reset),
        .start(start),
        
        // Connect the external memory interface
        .ecg_read_addr(ecg_read_addr),
        .ecg_read_data(ecg_read_data),
        
        .done(done),
        .final_mac_result(final_mac_result),
        .debug_window(debug_window),
        .relu_result(relu_result),
        .pooled_result(pooled_result),
        .total_score(total_score),
        .is_abnormal(is_abnormal),
        .is_normal(is_normal)
    );
// -------------------------------------------------------
    // 4. Clock Generation (100 MHz)
    // -------------------------------------------------------
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 10ns period
    end
// -------------------------------------------------------
    // 5. Stimulus and Checking Logic
    // -------------------------------------------------------
    initial begin
        // Initialize Inputs
        reset = 1;
        start = 0;

        // Wait for global reset to settle
        #100;
        reset = 0;
        #20;

        $display("========================================");
        $display("   TOP LEVEL TB: Final Validation       ");
        $display("========================================");

        // =========================================================
        // TEST CASE 1: NORMAL ECG
        // =========================================================
        $display("\n--- TEST 1: NORMAL ECG ---");
        
        $readmemh("test_ecg_normal.mem", testbench_ecg_mem);

        @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;

        // Wait for accelerator to finish
        wait(done == 1'b1);
        
        // FIX #1: Wait a few clock cycles for the classifier to latch the flags
        #40; 

        $display("  total_score  = %0d", $signed(total_score));
        $display("  is_abnormal  = %b   is_normal = %b", is_abnormal, is_normal);

        if (is_normal == 1'b1 && is_abnormal == 1'b0) begin
            $display("  RESULT: PASS ✓");
        end else begin
            $display("  RESULT: FAIL ✗");
        end

        // Wait a bit before starting the next test
        #200;

        // =========================================================
        // TEST CASE 2: ABNORMAL ECG
        // =========================================================
        $display("\n--- TEST 2: ABNORMAL ECG ---");
        
        // FIX #2: Pulse Reset to clear the 'done' signal and internal FSM!
        reset = 1;
        #40;
        reset = 0;
        #40;
        
        // Overwrite the testbench memory with the abnormal ECG data
        $readmemh("test_ecg_abnormal.mem", testbench_ecg_mem);
        
        @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;

        // Wait for accelerator to finish (done will now be 0 initially due to reset)
        wait(done == 1'b1);
        
        // FIX #1 again: Wait for flags to latch
        #40; 

        $display("  total_score  = %0d", $signed(total_score));
        $display("  is_abnormal  = %b   is_normal = %b", is_abnormal, is_normal);

        if (is_normal == 1'b0 && is_abnormal == 1'b1) begin // FIXED THIS LINE
            $display("  RESULT: PASS [OK]");
        end else begin
            $display("  RESULT: FAIL [ERROR]");
        end

        $display("\n========================================");
        $display("  TOP LEVEL SIMULATION COMPLETE         ");
        $display("========================================");
        $finish;
    end
endmodule