`timescale 1ns / 1ps

module basys3_top (
    input  wire        clk,          // 100 MHz on-board oscillator

    // Buttons
    input  wire        btnc,         // Centre  = global reset
    input  wire        btnl,         // Left    = AD8232 start capture

    // Switches
    input  wire        sw15,         // SW[15]: 0=UART mode, 1=sensor mode

    // UART
    input  wire        uart_rx,      // USB-UART bridge RX pin

    // AD8232 lead-off detect (connect when you have the sensor)
    input  wire        lo_plus,      // AD8232 LO+
    input  wire        lo_minus,     // AD8232 LO-

    // XADC analogue input (JXADC header pins)
    input  wire        vauxp6,       // JXADC Pin 1 (AD8232 OUTPUT)
    input  wire        vauxn6,       // JXADC Pin 7 (differential ref)

    // LEDs
    output wire [15:0] led
);

    wire reset = btnc;

    // ==============================================================
    // UART path
    // ==============================================================
    wire [7:0] uart_byte;
    wire       uart_valid;

    uart_rx #(.CLKS_PER_BIT(868)) u_uart (
        .clk     (clk),
        .rx      (uart_rx),
        .rx_data (uart_byte),
        .rx_done (uart_valid)
    );

    // UART byte counter + RAM writer
    reg [6:0]  uart_byte_count;
    reg        uart_sample_loaded;
    reg [6:0]  uart_ram_addr_r;
    reg [7:0]  uart_ram_data_r;
    reg        uart_ram_we_r;
    reg        uart_start_r;

    always @(posedge clk) begin
        uart_ram_we_r  <= 1'b0;
        uart_start_r   <= 1'b0;

        if (reset) begin
            uart_byte_count    <= 7'd0;
            uart_sample_loaded <= 1'b0;
        end else if (uart_valid && !uart_sample_loaded) begin
            uart_ram_addr_r   <= uart_byte_count;
            uart_ram_data_r   <= uart_byte;
            uart_ram_we_r     <= 1'b1;

            if (uart_byte_count == 7'd127) begin
                uart_sample_loaded <= 1'b1;
                uart_start_r       <= 1'b1;
            end else begin
                uart_byte_count <= uart_byte_count + 1;
            end
        end
    end

    // ==============================================================
    // XADC - Xilinx on-chip ADC
    // ==============================================================
    wire [15:0] xadc_do;
    wire        xadc_drdy;
    wire        xadc_den_w;
    wire [6:0]  xadc_daddr_w;

`ifdef HAVE_AD8232_HARDWARE
    xadc_wiz_0 u_xadc (
        .dclk_in     (clk),
        .reset_in    (reset),
        .di_in       (16'd0),
        .daddr_in    (xadc_daddr_w),
        .den_in      (xadc_den_w),
        .dwe_in      (1'b0),
        .do_out      (xadc_do),
        .drdy_out    (xadc_drdy),
        .busy_out    (),
        .channel_out (),
        .eoc_out     (),
        .alarm_out   (),
        .vp_in       (1'b0),
        .vn_in       (1'b0),
        .vauxp6      (vauxp6),
        .vauxn6      (vauxn6)
    );
`else
    assign xadc_do   = 16'd2048;
    assign xadc_drdy = 1'b0;
    wire _unused = vauxp6 ^ vauxn6;
`endif

    // ==============================================================
    // AD8232 Sampler FSM
    // ==============================================================
    wire [6:0]  adc_ram_addr;
    wire [7:0]  adc_ram_data;
    wire        adc_ram_we;
    wire        adc_start;
    wire        led_sampling, led_lead_off, led_ai_running;
    wire        done_wire;

    ad8232_sampler #(
        .CLOCKS_PER_SAMPLE (800_000),
        .N_SAMPLES         (128),
        .DEBOUNCE_COUNT    (1_000_000)
    ) u_sampler (
        .clk               (clk),
        .reset             (reset),
        .btn_start         (btnl),
        .lo_plus           (lo_plus),
        .lo_minus          (lo_minus),
        .xadc_data         (xadc_do),
        .xadc_drdy         (xadc_drdy),
        .xadc_den          (xadc_den_w),
        .xadc_daddr        (xadc_daddr_w),
        .ram_addr          (adc_ram_addr),
        .ram_data          (adc_ram_data),
        .ram_we            (adc_ram_we),
        .start_accelerator (adc_start),
        .done              (done_wire),
        .led_sampling      (led_sampling),
        .led_lead_off      (led_lead_off),
        .led_ai_running    (led_ai_running)
    );

    // ==============================================================
    // MODE MUX
    // ==============================================================
    wire [6:0] ram_addr_a = sw15 ? adc_ram_addr  : uart_ram_addr_r;
    wire [7:0] ram_data_a = sw15 ? adc_ram_data  : uart_ram_data_r;
    wire       ram_we_a   = sw15 ? adc_ram_we    : uart_ram_we_r;
    wire       start_accel = sw15 ? adc_start    : uart_start_r;

    // ==============================================================
    // Shared dual-port RAM
    // ==============================================================
    wire [7:0] ram_addr_b;  // Matched to 8-bit read address
    wire [7:0] ram_dout_b;

    // Pad the 7-bit write address to 8-bits to perfectly match your RAM module
    wire [7:0] padded_ram_addr_a = {1'b0, ram_addr_a};

    dual_port_ram u_ram (
        .clk    (clk),
        .weA    (ram_we_a),
        .addrA  (padded_ram_addr_a),
        .dinA   (ram_data_a),
        .addrB  (ram_addr_b),
        .doutB  (ram_dout_b)
    );

    // ==============================================================
    // NN Accelerator
    // ==============================================================
    wire is_normal, is_abnormal, done_accel;
    assign done_wire = done_accel;

    top_accelerator u_accel (
        .clk              (clk),
        .reset            (reset),
        .start            (start_accel),
        .ecg_read_addr    (ram_addr_b),
        .ecg_read_data    (ram_dout_b),
        .done             (done_accel),
        .is_abnormal      (is_abnormal),
        .is_normal        (is_normal)
        // Note: Debug outputs (final_mac_result, etc.) are left unconnected 
        // since they aren't needed at the top level for LEDs.
    );

    // ==============================================================
    // LED outputs
    // ==============================================================
    assign led[15]   = is_abnormal;         // ABNORMAL detected
    assign led[14]   = led_sampling;        // Sampling in progress
    assign led[13]   = led_lead_off;        // Electrode not attached
    assign led[12]   = led_ai_running;      // AI pipeline running
    assign led[11:8] = 4'b0000;
    assign led[7]    = done_accel;          // Inference complete
    assign led[6:1]  = 6'b000000;
    assign led[0]    = is_normal;           // NORMAL detected

endmodule