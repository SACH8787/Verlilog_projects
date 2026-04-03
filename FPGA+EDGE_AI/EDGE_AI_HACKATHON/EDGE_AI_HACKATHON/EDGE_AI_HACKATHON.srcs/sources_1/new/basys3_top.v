`timescale 1ns / 1ps
module basys3_top (
    input  wire        clk,        // 100 MHz Basys3 clock
    input  wire        reset_btn,  // Centre button = active-high reset
    input  wire        rx,         // USB-UART RX pin
    output wire [15:0] led         // 16 onboard LEDs
);

    // -----------------------------------------------------------------------
    // Internal signals
    // -----------------------------------------------------------------------
    wire [7:0]       rx_data;
    wire             rx_done;

    reg  [7:0]       rx_count        = 8'd0;
    reg              start_accelerator = 1'b0;
    reg              sample_loaded   = 1'b0;   // Prevent re-triggering

    wire [7:0]       accel_addr;
    wire signed [7:0] accel_data;
    wire             is_abnormal;
    wire             is_normal;
    wire             done_signal;

    // -----------------------------------------------------------------------
    // 1. UART Receiver (115200 baud @ 100 MHz -> CLKS_PER_BIT = 868)
    // -----------------------------------------------------------------------
    uart_rx #(.CLKS_PER_BIT(868)) receiver (
        .clk     (clk),
        .rx      (rx),
        .rx_data (rx_data),
        .rx_done (rx_done)
    );

    // -----------------------------------------------------------------------
    // 2. Data counter & one-shot start trigger
    // -----------------------------------------------------------------------
    always @(posedge clk) begin
        if (reset_btn) begin
            rx_count          <= 8'd0;
            start_accelerator <= 1'b0;
            sample_loaded     <= 1'b0;
        end else begin
            start_accelerator <= 1'b0;  // Default: de-assert each cycle

            if (rx_done && !sample_loaded) begin
                rx_count <= rx_count + 8'd1;

                if (rx_count == 8'd127) begin
                    // 128th byte received (index 127) -- fire start
                    start_accelerator <= 1'b1;
                    sample_loaded     <= 1'b1;  // Lock out further triggers
                end
            end
        end
    end

    // -----------------------------------------------------------------------
    // 3. Dual-port RAM: UART writes on Port A, accelerator reads on Port B
    // -----------------------------------------------------------------------
    dual_port_ram sample_buffer (
        .clk   (clk),
        .weA   (rx_done && !sample_loaded),  // Only write until buffer full
        .addrA (rx_count),                   // Pre-increment value (correct)
        .dinA  (rx_data),
        .addrB (accel_addr),
        .doutB (accel_data)
    );

    // -----------------------------------------------------------------------
    // 4. Neural Network Accelerator
    // -----------------------------------------------------------------------
    // Unused debug outputs are tied off to avoid undriven warnings
    wire signed [23:0] unused_mac;
    wire       [119:0] unused_dbg;
    wire signed [23:0] unused_relu;
    wire signed [23:0] unused_pool;
    wire signed [31:0] unused_score;

    top_accelerator ai_engine (
        .clk             (clk),
        .reset           (reset_btn),
        .start           (start_accelerator),
        .ecg_read_addr   (accel_addr),
        .ecg_read_data   (accel_data),
        .done            (done_signal),
        .final_mac_result(unused_mac),
        .debug_window    (unused_dbg),
        .relu_result     (unused_relu),
        .pooled_result   (unused_pool),
        .total_score     (unused_score),
        .is_abnormal     (is_abnormal),
        .is_normal       (is_normal)
    );

    // -----------------------------------------------------------------------
    // 5. LED routing
    // -----------------------------------------------------------------------
    assign led[15]   = is_abnormal;   // Red LED: ECG is abnormal
    assign led[0]    = is_normal;     // Green LED: ECG is normal
    assign led[7]    = done_signal;   // Middle LED: processing complete
    assign led[14:8] = 7'd0;
    assign led[6:1]  = 6'd0;

endmodule

