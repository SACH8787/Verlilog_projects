// ================================================================
// ad8232_sampler.v  (v2 - with Pan-Tompkins QRS detection)
// ================================================================
// WHAT CHANGED vs v1:
//   • pan_tompkins is instantiated as a sub-module (Stage 1)
//   • New circular pre-peak buffer: 64 int8 samples in shift register
//   • New FSM states:
//       S_WAIT_PEAK    - stream samples, wait for R-peak detection
//       S_COLLECT_TAIL - collect 64 more samples after the peak
//   • When S_COLLECT_TAIL finishes, write all 128 samples to RAM
//     (64 pre-peak from circular buffer + 64 post-peak)
//     then fire start_accelerator exactly as before
//
// WHAT DIDN'T CHANGE:
//   • All output ports: ram_addr, ram_data, ram_we,
//     start_accelerator, led_* - IDENTICAL to v1
//   • basys3_top.v: NO CHANGES needed at all
//   • UART mode: completely unaffected (SW[15]=0 mux in basys3_top)
//
// NEW PARAMETERS:
//   HALF_WIN = 64  - samples before and after R-peak (64+64=128 total)
//   For simulation, set CLOCKS_PER_SAMPLE=10, DEBOUNCE_COUNT=4
// ================================================================

`timescale 1ns / 1ps

module ad8232_sampler #(
    parameter CLOCKS_PER_SAMPLE = 800_000,  // 100MHz / 125Hz
    parameter N_SAMPLES         = 128,
    parameter DEBOUNCE_COUNT    = 1_000_000,
    parameter HALF_WIN          = 64         // 64 pre + 64 post = 128 total
)(
    input  wire        clk,
    input  wire        reset,
    input  wire        btn_start,
    input  wire        lo_plus,
    input  wire        lo_minus,

    // XADC DRP interface
    input  wire [15:0] xadc_data,
    input  wire        xadc_drdy,
    output wire        xadc_den,
    output wire [6:0]  xadc_daddr,

    // RAM write port (to dual_port_ram port A via mux in basys3_top)
    output reg  [6:0]  ram_addr,
    output reg  [7:0]  ram_data,
    output reg         ram_we,

    // NN pipeline control
    output reg         start_accelerator,
    input  wire        done,

    // Status LEDs
    output reg         led_sampling,
    output reg         led_lead_off,
    output reg         led_ai_running
);

    // ----------------------------------------------------------
    // FSM state encoding
    // ----------------------------------------------------------
    localparam S_IDLE         = 3'd0;
    localparam S_DEBOUNCE     = 3'd1;
    localparam S_WAIT_PEAK    = 3'd2;  // NEW: stream, detect R-peak
    localparam S_COLLECT_TAIL = 3'd3;  // NEW: collect 64 post-peak samples
    localparam S_WRITE_RAM    = 3'd4;  // NEW: write circular buf + tail to RAM
    localparam S_START_AI     = 3'd5;
    localparam S_WAIT_DONE    = 3'd6;
    localparam S_SHOW_RESULT  = 3'd7;

    reg [2:0]  state;
    reg [19:0] sample_timer;
    reg [19:0] debounce_timer;
    reg        xadc_req;

    // ----------------------------------------------------------
    // XADC addressing
    // ----------------------------------------------------------
    assign xadc_daddr = 7'h16;   // VAUXP6/VAUXN6
    assign xadc_den   = xadc_req;

    // ----------------------------------------------------------
    // Signal conditioning: DC remove + 8-bit scale
    // ----------------------------------------------------------
    wire [11:0]        xadc_12bit = xadc_data[15:4];
    wire signed [12:0] signed_val;
    assign signed_val = $signed({1'b0, xadc_12bit}) - 13'sd2048;
    wire signed [7:0]  int8_val;
    assign int8_val   = signed_val[11:4];

    wire lead_off = lo_plus | lo_minus;

    // ----------------------------------------------------------
    // Pan-Tompkins QRS detector (sub-module)
    // Receives every ADC sample via en_in = xadc_drdy
    // Resets at the start of each new measurement (pt_reset)
    // ----------------------------------------------------------
    reg        pt_reset;
    wire       r_peak_valid;
    wire [6:0] r_peak_idx;

    pan_tompkins u_pt (
        .clk              (clk),
        .reset            (pt_reset),
        .en_in            (xadc_drdy),
        .sample_in        (int8_val),
        .r_peak_valid     (r_peak_valid),
        .r_peak_sample_idx(r_peak_idx)
    );

    // ----------------------------------------------------------
    // Circular pre-peak buffer: 64-sample shift register
    // Newest sample at index 0, oldest at index HALF_WIN-1
    // When R-peak fires, this holds the 64 samples BEFORE the peak
    // ----------------------------------------------------------
    reg signed [7:0] pre_buf [0:63];   // circular buffer, 64 entries
    integer          pb;               // loop index

    // ----------------------------------------------------------
    // Post-peak collection buffer
    // ----------------------------------------------------------
    reg signed [7:0] post_buf [0:63];
    reg [6:0]        tail_count;       // counts post-peak samples collected

    // ----------------------------------------------------------
    // RAM write sequencer (used in S_WRITE_RAM)
    // ----------------------------------------------------------
    reg [7:0] wr_idx;   // 0..127: write address into RAM

    // ----------------------------------------------------------
    // FSM
    // ----------------------------------------------------------
    always @(posedge clk) begin
        if (reset) begin
            state             <= S_IDLE;
            sample_timer      <= 20'd0;
            debounce_timer    <= 20'd0;
            ram_addr          <= 7'd0;
            ram_data          <= 8'd0;
            ram_we            <= 1'b0;
            xadc_req          <= 1'b0;
            start_accelerator <= 1'b0;
            led_sampling      <= 1'b0;
            led_lead_off      <= 1'b0;
            led_ai_running    <= 1'b0;
            pt_reset          <= 1'b1;
            tail_count        <= 7'd0;
            wr_idx            <= 8'd0;
            for (pb = 0; pb < 64; pb = pb+1) pre_buf[pb]  <= 8'sd0;
            for (pb = 0; pb < 64; pb = pb+1) post_buf[pb] <= 8'sd0;
        end else begin
            // Default: deassert one-shot signals
            ram_we            <= 1'b0;
            xadc_req          <= 1'b0;
            start_accelerator <= 1'b0;
            pt_reset          <= 1'b0;
            led_lead_off      <= lead_off;

            case (state)

                // ------------------------------------------------
                S_IDLE: begin
                    led_sampling   <= 1'b0;
                    led_ai_running <= 1'b0;
                    tail_count     <= 7'd0;
                    wr_idx         <= 8'd0;
                    sample_timer   <= 20'd0;
                    if (btn_start) begin
                        debounce_timer <= 20'd0;
                        pt_reset       <= 1'b1;  // reset PT for fresh measurement
                        state          <= S_DEBOUNCE;
                    end
                end

                // ------------------------------------------------
                S_DEBOUNCE: begin
                    if (!btn_start) begin
                        state <= S_IDLE;
                    end else if (debounce_timer == DEBOUNCE_COUNT - 1) begin
                        state        <= S_WAIT_PEAK;
                        sample_timer <= 20'd0;
                        led_sampling <= 1'b1;
                        // Initialise pre_buf to zero
                        for (pb = 0; pb < 64; pb = pb+1) pre_buf[pb] <= 8'sd0;
                    end else begin
                        debounce_timer <= debounce_timer + 1;
                    end
                end

                // ------------------------------------------------
                // S_WAIT_PEAK: stream samples, feed to pan_tompkins,
                // fill circular pre-peak buffer.
                // Exit when r_peak_valid fires.
                // ------------------------------------------------
                S_WAIT_PEAK: begin
                    led_sampling <= 1'b1;

                    if (lead_off) begin
                        led_sampling <= ~led_sampling;
                    end else begin
                        sample_timer <= sample_timer + 1;

                        // Request XADC sample
                        if (sample_timer == CLOCKS_PER_SAMPLE - 2)
                            xadc_req <= 1'b1;

                        // On each new sample:
                        if (xadc_drdy) begin
                            sample_timer <= 20'd0;
                            // Shift circular buffer: newest at [0]
                            for (pb = 63; pb > 0; pb = pb-1)
                                pre_buf[pb] <= pre_buf[pb-1];
                            pre_buf[0] <= int8_val;
                        end

                        // R-peak detected by pan_tompkins
                        if (r_peak_valid) begin
                            tail_count   <= 7'd0;
                            state        <= S_COLLECT_TAIL;
                        end
                    end
                end

                // ------------------------------------------------
                // S_COLLECT_TAIL: collect 64 samples after the peak
                // ------------------------------------------------
                S_COLLECT_TAIL: begin
                    led_sampling <= 1'b1;

                    if (lead_off) begin
                        led_sampling <= ~led_sampling;
                    end else begin
                        sample_timer <= sample_timer + 1;

                        if (sample_timer == CLOCKS_PER_SAMPLE - 2)
                            xadc_req <= 1'b1;

                        if (xadc_drdy) begin
                            sample_timer       <= 20'd0;
                            post_buf[tail_count] <= int8_val;
                            tail_count         <= tail_count + 1;

                            if (tail_count == HALF_WIN - 1) begin
                                // All 64 post-peak samples collected
                                state        <= S_WRITE_RAM;
                                led_sampling <= 1'b0;
                                wr_idx       <= 8'd0;
                            end
                        end
                    end
                end

                // ------------------------------------------------
                // S_WRITE_RAM: write pre_buf (oldest first) then
                // post_buf to the shared dual_port_ram.
                // pre_buf[63] = oldest (64 samples before peak)
                // pre_buf[0]  = newest  (1 sample before peak)
                // post_buf[0..63] = 64 samples after peak
                //
                // RAM layout:
                //   addr  0..63: pre_buf[63] down to pre_buf[0]
                //   addr 64..127: post_buf[0] up to post_buf[63]
                //
                // Writes one byte per clock - 128 clocks total.
                // ------------------------------------------------
                S_WRITE_RAM: begin
                    // Write current byte.
                    // ram_we stays asserted for ALL 128 bytes including byte 127.
                    // The "default: ram_we <= 0" at the top of this always block
                    // will deassert it on the very next clock when state == S_START_AI.
                    // Previously, "ram_we <= 0" was written inside this state for
                    // wr_idx==127, which wins over "ram_we <= 1" in the same clock
                    // (last non-blocking assignment wins) -> byte 127 was lost.
                    ram_we   <= 1'b1;
                    ram_addr <= wr_idx[6:0];

                    if (wr_idx < 8'd64)
                        ram_data <= pre_buf[63 - wr_idx[5:0]];
                    else
                        ram_data <= post_buf[wr_idx[6:0] - 7'd64]; // FIX: was [5:0]-0

                    if (wr_idx == 8'd127)
                        state <= S_START_AI;          // no ram_we=0 here
                    else
                        wr_idx <= wr_idx + 1;
                end

                // ------------------------------------------------
                S_START_AI: begin
                    start_accelerator <= 1'b1;
                    led_ai_running    <= 1'b1;
                    state             <= S_WAIT_DONE;
                end

                // ------------------------------------------------
                S_WAIT_DONE: begin
                    led_ai_running <= 1'b1;
                    if (done) begin
                        led_ai_running <= 1'b0;
                        state          <= S_SHOW_RESULT;
                    end
                end

                // ------------------------------------------------
                S_SHOW_RESULT: begin
                    if (btn_start) state <= S_IDLE;
                end

                default: state <= S_IDLE;

            endcase
        end
    end

endmodule