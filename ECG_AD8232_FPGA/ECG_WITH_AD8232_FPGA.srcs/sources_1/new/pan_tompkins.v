// ================================================================
// pan_tompkins.v  -  Pan-Tompkins QRS Detector
// ================================================================
// Instantiated INSIDE ad8232_sampler.v as a sub-module.
// basys3_top.v does NOT know this module exists.
//
// INTERFACE:
//   clk, reset        - standard synchronous reset
//   en_in             - 1 for exactly 1 clock when a new ADC sample
//                       is available (connects to xadc_drdy)
//   sample_in         - the raw int8 ECG sample (from int8_val in sampler)
//   r_peak_valid      - pulses HIGH for exactly 1 clock when R-peak found
//   r_peak_sample_idx - sample index (0-based) where the R-peak was detected
//                       in the current streaming window
//
// ALGORITHM (5 stages, all integer, no division):
//   1. Low-pass  IIR  (cutoff ~11 Hz at 125 Hz sample rate)
//   2. High-pass IIR  (cutoff  ~5 Hz - removes baseline wander)
//   3. Derivative FIR (5-tap, emphasises QRS steep slopes)
//   4. Squaring       (all positive, peak amplification)
//   5. Moving window integrator (15 samples)
//   6. Adaptive threshold + falling-edge peak detection
//
// BUG FIXED vs original draft:
//   r_peak_sample_idx used "sample_counter - 1" which gave N-2 due to
//   non-blocking semantics. Corrected to "sample_counter" (= pre-increment
//   old value = current sample index N-1 for the Nth sample).
// ================================================================

`timescale 1ns / 1ps

module pan_tompkins (
    input  wire        clk,
    input  wire        reset,
    input  wire        en_in,               // pulse once per ADC sample
    input  wire signed [7:0] sample_in,     // raw int8 ECG sample

    output wire        r_peak_valid,        // 1 clock pulse when R-peak found
    output reg  [6:0]  r_peak_sample_idx    // 0-based sample index of R-peak
);

    integer k;  // loop variable for reset init

    // ----------------------------------------------------------
    // Stage 1: Low-pass IIR filter
    //   H(z) = (1 - z^-6)^2 / (1 - z^-1)^2
    //   Difference eq: y[n] = 2y[n-1] - y[n-2] + x[n] - 2x[n-6] + x[n-12]
    //   All 16-bit signed arithmetic - no overflow risk at int8 input.
    // ----------------------------------------------------------
    reg signed [15:0] lp_y1;       // y[n-1]
    reg signed [15:0] lp_y2;       // y[n-2]
    reg signed  [7:0] lp_xd [0:12]; // x delay line (index 0 = newest)

    wire signed [15:0] lp_out = (2 * lp_y1) - lp_y2
                                 + $signed(sample_in)
                                 - (2 * $signed(lp_xd[5]))
                                 + $signed(lp_xd[11]);

    always @(posedge clk) begin
        if (reset) begin
            lp_y1 <= 16'sd0;
            lp_y2 <= 16'sd0;
            for (k = 0; k < 13; k = k+1) lp_xd[k] <= 8'sd0;
        end else if (en_in) begin
            for (k = 12; k > 0; k = k-1) lp_xd[k] <= lp_xd[k-1];
            lp_xd[0] <= sample_in;
            lp_y2    <= lp_y1;
            lp_y1    <= lp_out;
        end
    end

    // ----------------------------------------------------------
    // Stage 2: High-pass IIR filter
    //   Derived from: hp(z) = (z^-16 - (1/32)(1+z^-1)/(1-z^-1))
    //   Approx integer form:
    //     y[n] = lp[n-16] - ((y[n-1] + lp[n] - lp[n-32]) >>> 5)
    //   Uses 32-tap LP delay line (indices 0..32, 0=newest).
    // ----------------------------------------------------------
    reg signed [15:0] hp_y1;
    reg signed [15:0] lp_hpd [0:32];  // LP output delay for HP input

    wire signed [15:0] hp_out = lp_hpd[16]
                                 - ((hp_y1 + lp_out - lp_hpd[32]) >>> 5);

    always @(posedge clk) begin
        if (reset) begin
            hp_y1 <= 16'sd0;
            for (k = 0; k < 33; k = k+1) lp_hpd[k] <= 16'sd0;
        end else if (en_in) begin
            for (k = 32; k > 0; k = k-1) lp_hpd[k] <= lp_hpd[k-1];
            lp_hpd[0] <= lp_out;
            hp_y1     <= hp_out;
        end
    end

    // ----------------------------------------------------------
    // Stage 3: Causal 5-point derivative FIR
    //   Paper: y[n] = (-x[n-2] - 2x[n-1] + 2x[n+1] + x[n+2]) / 8
    //   Causal (2-sample delayed) equivalent:
    //     y[n] = (-x[n] - 2x[n-1] + 2x[n-3] + x[n-4]) / 8
    //   Delay line: dly[0]=newest=x[n], dly[4]=oldest=x[n-4]
    //   NOTE: dly[0] holds hp_out from the PREVIOUS en_in (non-blocking),
    //   so effectively dly[0]=x[n-1] when computing deriv for sample n.
    //   This adds 1 extra cycle of group delay - acceptable.
    // ----------------------------------------------------------
    reg signed [15:0] dly [0:4];

    wire signed [15:0] deriv_out = ((-dly[4] - (2 * dly[3])
                                      + (2 * dly[1]) + dly[0]) >>> 3);

    always @(posedge clk) begin
        if (reset) begin
            for (k = 0; k < 5; k = k+1) dly[k] <= 16'sd0;
        end else if (en_in) begin
            for (k = 4; k > 0; k = k-1) dly[k] <= dly[k-1];
            dly[0] <= hp_out;
        end
    end

    // ----------------------------------------------------------
    // Stage 4: Squaring  y[n] = x[n]^2
    //   Uses one DSP48E1 slice.
    //   sq_out is registered: captures deriv_out (which reads PREVIOUS
    //   dly values) then dly updates - correct 1-cycle pipeline. ✓
    // ----------------------------------------------------------
    (* use_dsp = "yes" *) reg signed [31:0] sq_out;

    always @(posedge clk) begin
        if (reset)      sq_out <= 32'sd0;
        else if (en_in) sq_out <= deriv_out * deriv_out;
    end

    // ----------------------------------------------------------
    // Stage 5: Moving Window Integrator (15-sample window)
    //   y[n] = (1/15) * sum(x[n-14]..x[n])
    //   Integer approx: running sum >>> 4  (÷16, error <7%)
    // ----------------------------------------------------------
    reg signed [31:0] mwi_dly [0:14];
    reg signed [35:0] mwi_sum;           // 36-bit prevents overflow

    wire signed [31:0] mwi_out = mwi_sum[35:4]; // >>> 4

    always @(posedge clk) begin
        if (reset) begin
            mwi_sum <= 36'sd0;
            for (k = 0; k < 15; k = k+1) mwi_dly[k] <= 32'sd0;
        end else if (en_in) begin
            mwi_sum <= mwi_sum + $signed({4'sd0, sq_out})
                               - $signed({4'sd0, mwi_dly[14]});
            for (k = 14; k > 0; k = k-1) mwi_dly[k] <= mwi_dly[k-1];
            mwi_dly[0] <= sq_out;
        end
    end

    // ----------------------------------------------------------
    // Stage 6: Adaptive threshold + R-peak detection
    //
    //   Threshold: 25% of running_max (>>> 2)
    //   running_max decays slowly each sample (max >>> 7 per sample)
    //   so it adapts to amplitude changes without a fixed window.
    //
    //   Peak detection: signal rises above threshold (above_thresh=1),
    //   then starts falling (is_falling=1) -> peak was at previous sample.
    //
    //   BUG FIX: r_peak_sample_idx = sample_counter (NOT sample_counter-1)
    //   Reason: non-blocking means sample_counter RHS = OLD value = index
    //   of the CURRENT sample (pre-increment). The peak is at the sample
    //   BEFORE the falling edge, which IS the current sample. ✓
    //
    //   Minimum signal guard: running_max must exceed 1000 before
    //   threshold activates, preventing false triggers on noise/flat signal.
    // ----------------------------------------------------------
    reg signed [31:0] running_max;
    reg signed [31:0] mwi_prev;
    reg               above_thresh;
    reg               peak_found_r;
    reg [6:0]         sample_counter;   // counts en_in pulses, 0-based

    wire signed [31:0] threshold  = running_max >>> 2;
    wire               over_thresh = ($signed(mwi_out) > $signed(threshold))
                                     && (running_max > 32'sd1000);
    wire               is_falling  = ($signed(mwi_out) < $signed(mwi_prev))
                                     && above_thresh;

    assign r_peak_valid = peak_found_r;

    always @(posedge clk) begin
        if (reset) begin
            running_max    <= 32'sd0;
            mwi_prev       <= 32'sd0;
            above_thresh   <= 1'b0;
            peak_found_r   <= 1'b0;
            r_peak_sample_idx <= 7'd0;
            sample_counter <= 7'd0;
        end else begin
            peak_found_r <= 1'b0;   // default: deassert every cycle

            if (en_in) begin
                // Update adaptive running max
                if ($signed(mwi_out) > $signed(running_max))
                    running_max <= mwi_out;
                else if (running_max > 32'sd0)
                    running_max <= running_max - (running_max >>> 7);

                // Above-threshold tracking
                if (over_thresh)
                    above_thresh <= 1'b1;

                // Peak = was above thresh, now falling
                // FIXED: use sample_counter (pre-increment OLD value = current idx)
                if (is_falling) begin
                    above_thresh      <= 1'b0;
                    peak_found_r      <= 1'b1;
                    r_peak_sample_idx <= sample_counter;  // ← FIXED (was sample_counter-1)
                end

                mwi_prev       <= mwi_out;
                sample_counter <= sample_counter + 1;
            end
        end
    end

endmodule