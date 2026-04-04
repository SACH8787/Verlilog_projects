`timescale 1ns / 1ps

module tb_full();

    reg clk;
    reg reset;
    reg start;

    wire [7:0]        ecg_read_addr;
    reg signed [7:0]  ecg_read_data; // Changed from wire to reg
    wire              done;
    wire signed [23:0] final_mac_result;
    wire [119:0]      debug_window;
    wire signed [23:0] relu_result;
    wire signed [23:0] pooled_result;
    wire signed [31:0] total_score;
    wire              is_abnormal;
    wire              is_normal;

    // ECG memory array
    reg signed [7:0] ecg_mem [0:127];
    
    // FIX: Synchronous read to correctly mimic FPGA Block RAM latency
    always @(posedge clk) begin
        ecg_read_data <= ecg_mem[ecg_read_addr];
    end

    top_accelerator uut (
        .clk             (clk),
        .reset           (reset),
        .start           (start),
        .ecg_read_addr   (ecg_read_addr),
        .ecg_read_data   (ecg_read_data),
        .done            (done),
        .final_mac_result(final_mac_result),
        .debug_window    (debug_window),
        .relu_result     (relu_result),
        .pooled_result   (pooled_result),
        .total_score     (total_score),
        .is_abnormal     (is_abnormal),
        .is_normal       (is_normal)
    );

    always #5 clk = ~clk;  // 100 MHz Clock

    integer pass_count = 0;
    integer fail_count = 0;

    task run_test;
        input [255:0] label;
        input signed [31:0] expected_score;
        input expected_is_abnormal;
        begin
            // Reset
            reset = 1; start = 0;
            repeat(4) @(posedge clk); #1;
            reset = 0;
            repeat(2) @(posedge clk); #1;

            // Pulse start
            start = 1; @(posedge clk); #1;
            start = 0;

            // Wait for done
            wait(done == 1);
            repeat(3) @(posedge clk); // Give classifier time to update flags

            $display("");
            $display("--- %0s ---", label);
            $display("  total_score  = %0d  (Python expected ~%0d)", total_score, expected_score);
            $display("  is_abnormal  = %0b   is_normal = %0b", is_abnormal, is_normal);

            if (is_abnormal == expected_is_abnormal) begin
                $display("  RESULT: PASS ✓");
                pass_count = pass_count + 1;
            end else begin
                $display("  RESULT: FAIL ✗  (got %0s, expected %0s)",
                         is_abnormal ? "ABNORMAL" : "NORMAL",
                         expected_is_abnormal ? "ABNORMAL" : "NORMAL");
                fail_count = fail_count + 1;
            end
        end
    endtask

    initial begin
        clk = 0;
        reset = 1;
        start = 0;

        $display("========================================");
        $display(" tb_full: ECG Accelerator Tests");
        $display("========================================");

        // --- TEST 1: Normal ECG ---
        $readmemh("test_ecg_normal.mem", ecg_mem);
        run_test("TEST 1: NORMAL ECG", -550551, 1'b0);

        // --- TEST 2: Abnormal ECG ---
        $readmemh("test_ecg_abnormal.mem", ecg_mem);
        run_test("TEST 2: ABNORMAL ECG", 1181310, 1'b1);

        $display("");
        $display("========================================");
        $display(" RESULTS: %0d PASSED  %0d FAILED", pass_count, fail_count);
        if (fail_count == 0)
            $display(" STATUS: ALL TESTS PASSED - ready to program FPGA ✓");
        else
            $display(" STATUS: FAILURES DETECTED");
        $display("========================================");
        $finish;
    end

    // Safety timeout
    initial begin
        #5_000_000;
        $display("TIMEOUT - simulation took too long");
        $finish;
    end

endmodule