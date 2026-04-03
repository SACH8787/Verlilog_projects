`timescale 1ns / 1ps
module top_accelerator (
    input  wire        clk,
    input  wire        reset,
    input  wire        start,

    output wire [7:0]  ecg_read_addr,
    input  wire signed [7:0] ecg_read_data,

    output wire        done,
    output wire signed [23:0] final_mac_result,
    output wire [119:0] debug_window,
    output wire signed [23:0] relu_result,
    output wire signed [23:0] pooled_result,
    output wire signed [31:0] total_score,
    output wire        is_abnormal,
    output wire        is_normal
);
    wire classifier_valid_wire;
    wire [7:0]   weight_addr;
    wire signed [7:0]  weight_data;
    wire         mac_enable;
    wire         mac_clear;
    wire [119:0]  window_data;
    wire [1919:0] filter_weights;

    assign debug_window = window_data;

    rom_memory #(
        .FILE_NAME("conv_weights.mem"),
        .MEM_DEPTH(240)
    ) weight_rom (
        .clk     (clk),
        .address (weight_addr),
        .data_out(weight_data)
    );

    controller_fsm fsm_inst (
        .clk            (clk),
        .reset          (reset),
        .start          (start),
        .ecg_addr       (ecg_read_addr),
        .ecg_data_in    (ecg_read_data),
        .weight_addr    (weight_addr),
        .weight_data_in (weight_data),
        .mac_enable     (mac_enable),
        .mac_clear      (mac_clear),
        .window_out     (window_data),
        .weight_out     (filter_weights),
        .done           (done),
        .classifier_valid(classifier_valid_wire)
    );

    conv1d_engine mac_inst (
        .clk           (clk),
        .reset         (reset),
        .enable        (mac_enable),
        .clear_acc     (mac_clear),
        .window_data   (window_data),
        .filter_weights(filter_weights),
        .conv_sum      (final_mac_result)
    );

    // relu and max_pool kept for waveform debugging only
    relu relu_inst (
        .data_in (final_mac_result),
        .data_out(relu_result)
    );

    max_pool pool_inst (
        .clk       (clk),
        .reset     (reset),
        .relu_in   (relu_result),
        .pooled_out(pooled_result)
    );

    // Classifier receives final_mac_result DIRECTLY (not relu_result)
    // so negative FC scores for normal ECGs are preserved and accumulated.
    classifier classifier_inst (
        .clk        (clk),
        .reset      (reset),
        .done       (done),
        .valid_in   (classifier_valid_wire),
        .pooled_in  (final_mac_result),   // direct - bypass relu + max_pool
        .total_score(total_score),
        .is_abnormal(is_abnormal),
        .is_normal  (is_normal)
    );

endmodule