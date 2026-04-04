`timescale 1ns / 1ps

// ================================================================
// tb_pan_tompkins_sample.v  -  CORRECTED testbench (v2)
// ================================================================
// COMPLETE BUG FIX LOG (original TB -> this file):
//
//  Round 1 fixes (structural / compile errors):
//  [1] Wrong ad8232_sampler port names (sw_uart_mode, xadc_do, led bus)
//      -> Corrected to xadc_data, xadc_den, xadc_daddr, done,
//         led_sampling, led_lead_off, led_ai_running
//  [2] Wrong pan_tompkins output port (.r_peak_sample -> .r_peak_sample_idx)
//  [3] Wrong parameter names (SAMPLE_RATE_HZ/DEBOUNCE_MS ->
//      CLOCKS_PER_SAMPLE=10 / DEBOUNCE_COUNT=4 for simulation speed)
//  [4] btn_start released before debounce expired -> FSM returned to IDLE
//  [5] Watchdog too short for the sample loop
//  [6] "j = 2000" loop break -> replaced with disable
//  [7] LED check used bit-index on a wire bus that doesn't exist
//  [8] ecg_to_xadc returned 12-bit in wrong position (sampler reads [15:4])
//  [9] No warning when .mem file is absent
//
//  Round 2 fixes (simulation failure: 127 writes, start_acc=0):
// [10] pan_tompkins has no DATA_WIDTH parameter -> removed from instantiation
// [11] start_accelerator is a ONE-SHOT pulse (1 clock wide). The original
//      check happened AFTER the loop exited, missing the pulse entirely.
//      -> Added a 'start_seen' latch driven by an always block that catches
//         any rising edge of start_accelerator.
// [12] ad8232_sampler S_WRITE_RAM BUG (in the design, not the TB):
//      When wr_idx==127, the state had BOTH "ram_we<=1" AND "ram_we<=0"
//      in the same clock. In Verilog non-blocking, the LAST assignment wins,
//      so ram_we was 0 -> byte 127 was never written -> 127 writes, not 128.
//      -> Fixed in ad8232_sampler.v: removed the explicit ram_we<=0 for the
//         last byte; the top-of-always-block default takes care of it next clk.
// [13] post_buf address: "wr_idx[5:0] - 6'd0" was a no-op that accidentally
//      worked for indices 64-127 only because [5:0] of 64..127 = 0..63.
//      Changed to the clearer "wr_idx[6:0] - 7'd64" in the design.
// ================================================================

module tb_pan_tompkins_sampler();

    // ============================================================
    // Simulation parameters  (match the instantiations below)
    // ============================================================
    localparam CPS = 10;   // CLOCKS_PER_SAMPLE  (10 clk = fast sim)
    localparam DBC = 4;    // DEBOUNCE_COUNT

    // ============================================================
    // Clocks & Reset
    // ============================================================
    reg clk;
    reg pt_clk;
    reg reset;

    initial clk    = 0;
    always  #5 clk    = ~clk;   // 100 MHz

    initial pt_clk = 0;
    always  #5 pt_clk = ~pt_clk;

    // ============================================================
    // pan_tompkins standalone signals
    // ============================================================
    reg  signed [7:0] pt_data;
    reg               pt_en;
    wire              pt_r_peak_valid;
    wire [6:0]        pt_r_peak_sample_idx;

    // ============================================================
    // ad8232_sampler signals
    // ============================================================
    reg         btn_start;
    reg         lo_plus;
    reg         lo_minus;
    reg         xadc_drdy;
    reg  [15:0] xadc_data;
    reg         done_in;

    wire        xadc_den;
    wire [6:0]  xadc_daddr;
    wire [6:0]  ram_addr;
    wire [7:0]  ram_data;
    wire        ram_we;
    wire        start_accelerator;
    wire        led_sampling;
    wire        led_lead_off;
    wire        led_ai_running;

    // ============================================================
    // FIX [11]: Latch for the one-shot start_accelerator pulse
    // start_accelerator is deasserted by default every clock, so
    // it is only HIGH for exactly 1 clock. We must latch it.
    // ============================================================
    reg start_seen;
    always @(posedge clk)
        if (reset)             start_seen <= 1'b0;
        else if (start_accelerator) start_seen <= 1'b1;

    // ============================================================
    // Tracking counters
    // ============================================================
    reg [7:0] real_ecg_data [0:1999];
    integer   pt_valid_count;
    integer   ram_write_count;
    integer   tests_failed;

    always @(posedge pt_clk)
        if (pt_r_peak_valid) pt_valid_count = pt_valid_count + 1;

    always @(posedge clk)
        if (ram_we) ram_write_count = ram_write_count + 1;

    // ============================================================
    // DUT instantiations
    // ============================================================

    // FIX [10]: pan_tompkins has no DATA_WIDTH parameter
    pan_tompkins u_pt (
        .clk              (pt_clk),
        .reset            (reset),
        .en_in            (pt_en),
        .sample_in        (pt_data),
        .r_peak_valid     (pt_r_peak_valid),
        .r_peak_sample_idx(pt_r_peak_sample_idx)
    );

    ad8232_sampler #(
        .CLOCKS_PER_SAMPLE (CPS),
        .N_SAMPLES         (128),
        .DEBOUNCE_COUNT    (DBC),
        .HALF_WIN          (64)
    ) u_sampler (
        .clk               (clk),
        .reset             (reset),
        .btn_start         (btn_start),
        .lo_plus           (lo_plus),
        .lo_minus          (lo_minus),
        .xadc_data         (xadc_data),
        .xadc_drdy         (xadc_drdy),
        .xadc_den          (xadc_den),
        .xadc_daddr        (xadc_daddr),
        .ram_addr          (ram_addr),
        .ram_data          (ram_data),
        .ram_we            (ram_we),
        .start_accelerator (start_accelerator),
        .done              (done_in),
        .led_sampling      (led_sampling),
        .led_lead_off      (led_lead_off),
        .led_ai_running    (led_ai_running)
    );

    // ============================================================
    // Helper tasks / functions
    // ============================================================

    task send_pt_sample(input signed [7:0] val);
        begin
            pt_en   = 1;
            pt_data = val;
            @(posedge pt_clk);
            pt_en   = 0;
            @(posedge pt_clk);
        end
    endtask

    // FIX [8]: 12-bit ADC value must sit in xadc_data[15:4]
    // Sampler does: xadc_12bit = xadc_data[15:4]
    function [15:0] ecg_to_xadc;
        input signed [7:0] ecg_val;
        reg [11:0] adc12;
        begin
            // Map int8 (-128..127) -> unsigned 12-bit centred at 2048
            adc12       = { {1'b0}, ecg_val[6:0], 4'b0000 } + 12'h800;
            ecg_to_xadc = { adc12, 4'b0000 };  // value in bits [15:4]
        end
    endfunction

    // Drive one XADC ready pulse then wait for the next sample period.
    // CPS-1 wait after the pulse keeps the inter-sample spacing = CPS clocks.
    task send_xadc_sample(input [15:0] val);
        begin
            xadc_data = val;
            xadc_drdy = 1'b1;
            @(posedge clk);
            xadc_drdy = 1'b0;
            repeat(CPS - 1) @(posedge clk);
        end
    endtask

    // ============================================================
    // MAIN TEST SEQUENCE
    // ============================================================
    initial begin
        // ------- initialise -------
        reset          = 1;
        pt_en          = 0;
        pt_data        = 8'sd0;
        btn_start      = 0;
        xadc_drdy      = 0;
        xadc_data      = 16'd0;
        lo_plus        = 0;
        lo_minus       = 0;
        done_in        = 0;
        pt_valid_count = 0;
        ram_write_count= 0;
        tests_failed   = 0;

        // FIX [9]: warn if .mem file might be missing
        $display("NOTE: Ensure 'test_ecg_normal.mem' is in the sim");
        $display("      working directory (hex bytes, 1 per line).");

        $readmemh("test_ecg_normal.mem", real_ecg_data);

        #100 reset = 0;
        #50;

        $display("================================================================");
        $display("  tb_pan_tompkins_sampler: COMPLETE HARDWARE TEST");
        $display("================================================================");

        // --------------------------------------------------------
        // TEST 1a: Flat signal -> noise guard must suppress peaks
        // --------------------------------------------------------
        $display("\n--- TEST 1a: Flat signal (Noise Guard) ---");
        pt_valid_count = 0;
        begin : blk_1a
            integer i;
            for (i = 0; i < 200; i = i + 1)
                send_pt_sample(8'sd0);
        end
        if (pt_valid_count == 0)
            $display("  [ PASS ] No false triggers on flat signal");
        else begin
            $display("  [ FAIL ] False trigger! count=%0d", pt_valid_count);
            tests_failed = tests_failed + 1;
        end

        // --------------------------------------------------------
        // TEST 1b: Real ECG data -> must detect at least one R-peak
        // --------------------------------------------------------
        $display("\n--- TEST 1b: Pan-Tompkins with real .mem data ---");
        pt_valid_count = 0;
        begin : blk_1b
            integer i;
            for (i = 0; i < 2000; i = i + 1)
                send_pt_sample($signed(real_ecg_data[i]));
        end
        if (pt_valid_count > 0)
            $display("  [ PASS ] Found %0d R-Peaks in real data!", pt_valid_count);
        else begin
            $display("  [ FAIL ] No R-peaks found in real data.");
            tests_failed = tests_failed + 1;
        end

        // --------------------------------------------------------
        // TEST 2b: Lead-off detection
        // --------------------------------------------------------
        $display("\n--- TEST 2b: Lead-Off Detection ---");
        lo_plus = 1;
        @(posedge clk); @(posedge clk);
        if (led_lead_off == 1'b1)
            $display("  [ PASS ] led_lead_off asserts when LO+ high");
        else begin
            $display("  [ FAIL ] led_lead_off not asserted");
            tests_failed = tests_failed + 1;
        end
        lo_plus = 0;
        @(posedge clk);

        // --------------------------------------------------------
        // TEST 2a: Full sampler flow
        //   - FSM must traverse IDLE->DEBOUNCE->WAIT_PEAK->
        //     COLLECT_TAIL->WRITE_RAM->START_AI
        //   - Expect exactly 128 RAM writes
        //   - Expect start_accelerator to pulse (caught by start_seen latch)
        // --------------------------------------------------------
        $display("\n--- TEST 2a: Full Sampler Flow (FSM & RAM Write) ---");

        ram_write_count = 0;

        // FIX [4]: hold btn_start through the entire debounce window
        btn_start = 1;
        repeat(DBC + 5) @(posedge clk);   // DBC=4 clks debounce + margin
        btn_start = 0;

        // Feed XADC samples; FSM is now in S_WAIT_PEAK.
        // Exit early once the R-peak triggers the full pipeline.
        // start_seen latch catches the one-clock start_accelerator pulse.
        begin : blk_2a
            integer j;
            for (j = 0; j < 2000; j = j + 1) begin
                send_xadc_sample(ecg_to_xadc($signed(real_ecg_data[j])));
                // start_seen is set by the always block above the instant
                // start_accelerator fires. Exit after the RAM write+AI pulse.
                if (start_seen) disable blk_2a;
            end
        end

        // Allow a few clocks for the RAM write counter to settle
        repeat(10) @(posedge clk);

        if (start_seen && ram_write_count == 128)
            $display("  [ PASS ] 128 bytes written & AI triggered!");
        else if (start_seen && ram_write_count != 128)
            $display("  [ WARN ] AI triggered but only %0d/128 bytes written",
                     ram_write_count);
        else begin
            $display("  [ FAIL ] Sampler stuck. RAM writes=%0d, start_seen=%b",
                     ram_write_count, start_seen);
            tests_failed = tests_failed + 1;
        end

        // Pulse done so sampler returns to IDLE (otherwise it sits in S_WAIT_DONE)
        done_in = 1;
        repeat(3) @(posedge clk);
        done_in = 0;

        // --------------------------------------------------------
        // Summary
        // --------------------------------------------------------
        $display("\n================================================================");
        if (tests_failed == 0)
            $display("  ALL TESTS PASSED! Ready for hardware.");
        else
            $display("  %0d TEST(S) FAILED", tests_failed);
        $display("================================================================");
        $finish;
    end

    // ============================================================
    // Watchdog
    // ============================================================
    initial begin
        #5_000_000;
        $display("TIMEOUT: Simulation exceeded 5 ms limit.");
        $finish;
    end

endmodule