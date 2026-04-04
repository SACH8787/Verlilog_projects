`timescale 1ns / 1ps
//==============================================================================
// controller_fsm.v
//
// PIPELINE DELAY = 12 cycles - matches conv1d_engine with single-cycle pe_mac:
//   Stage  1: pe_mac (single-cycle multiply)
//   Stage  2: stg1
//   Stage  3: stg2  } combined always block, non-blocking = 2 real stages
//   Stage  4: stg3  }
//   Stage  5: filter_sum
//   Stage  6: relu_reg
//   Stage  7: weighted_reg
//   Stage  8: gt_stg1  }
//   Stage  9: gt_stg2  } combined always block, non-blocking = 4 real stages
//   Stage 10: gt_stg3  }
//   Stage 11: final_total }
//   Stage 12: conv_sum_reg
//
// val_pipe = 12-bit, classifier_valid = val_pipe[11]
//==============================================================================
module controller_fsm (
    input  wire        clk,
    input  wire        reset,
    input  wire        start,

    output reg  [7:0]  ecg_addr,
    input  wire signed [7:0] ecg_data_in,

    output reg  [7:0]  weight_addr,
    input  wire signed [7:0] weight_data_in,

    output reg         mac_enable,
    output reg         mac_clear,

    output reg  [119:0]  window_out,
    output reg  [1919:0] weight_out,

    output reg         done,
    output wire        classifier_valid
);

    localparam IDLE           = 3'd0;
    localparam LOAD_WEIGHTS   = 3'd1;
    localparam FILL_WINDOW    = 3'd2;
    localparam COMPUTE        = 3'd3;
    localparam SHIFT_READ     = 3'd4;
    localparam DONE_STATE     = 3'd5;
    localparam DRAIN_PIPELINE = 3'd6;

    reg [2:0] state;
    reg [8:0] fill_counter;

    // 12-bit shift register - one bit per pipeline stage
    reg [11:0] val_pipe;

    always @(posedge clk) begin
        if (reset) begin
            state        <= IDLE;
            ecg_addr     <= 8'd0;
            weight_addr  <= 8'd0;
            mac_enable   <= 1'b0;
            mac_clear    <= 1'b1;
            done         <= 1'b0;
            window_out   <= 120'd0;
            weight_out   <= 1920'd0;
            fill_counter <= 9'd0;
        end else begin

            mac_enable <= 1'b0;
            mac_clear  <= 1'b0;

            case (state)
                IDLE: begin
                    mac_clear    <= 1'b1;
                    done         <= 1'b0;
                    ecg_addr     <= 8'd0;
                    weight_addr  <= 8'd0;
                    fill_counter <= 9'd0;
                    if (start) state <= LOAD_WEIGHTS;
                end

                LOAD_WEIGHTS: begin
                    mac_clear <= 1'b1;
                    if (fill_counter > 9'd0)
                        weight_out <= {weight_data_in, weight_out[1919:8]};
                    if (fill_counter == 9'd240) begin
                        state        <= FILL_WINDOW;
                        fill_counter <= 9'd0;
                        ecg_addr     <= 8'd0;
                    end else begin
                        weight_addr  <= weight_addr + 8'd1;
                        fill_counter <= fill_counter + 9'd1;
                    end
                end

                FILL_WINDOW: begin
                    mac_clear <= 1'b1;
                    if (fill_counter > 9'd0)
                        window_out <= {ecg_data_in, window_out[119:8]};
                    if (fill_counter == 9'd15) begin
                        state <= COMPUTE;
                    end else begin
                        ecg_addr     <= ecg_addr + 8'd1;
                        fill_counter <= fill_counter + 9'd1;
                    end
                end

                COMPUTE: begin
                    mac_enable <= 1'b1;
                    state      <= SHIFT_READ;
                end

                SHIFT_READ: begin
                    mac_clear <= 1'b1;
                    if (ecg_addr >= 8'd128) begin
                        state <= DRAIN_PIPELINE;
                    end else begin
                        window_out <= {ecg_data_in, window_out[119:8]};
                        ecg_addr   <= ecg_addr + 8'd1;
                        state      <= COMPUTE;
                    end
                end

                DRAIN_PIPELINE: begin
                    if (val_pipe == 12'd0)
                        state <= DONE_STATE;
                end

                DONE_STATE: begin
                    done <= 1'b1;
                end

                default: state <= IDLE;
            endcase
        end
    end

    // 12-stage shift register tracking mac_enable through the pipeline
    always @(posedge clk) begin
        if (reset) val_pipe <= 12'd0;
        else       val_pipe <= {val_pipe[10:0], mac_enable};
    end

    // classifier_valid fires 12 cycles after mac_enable
    assign classifier_valid = val_pipe[11];

endmodule