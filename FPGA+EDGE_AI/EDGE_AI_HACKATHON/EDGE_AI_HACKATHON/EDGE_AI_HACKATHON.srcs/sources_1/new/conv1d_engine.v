`timescale 1ns / 1ps
//==============================================================================
// conv1d_engine.v  -  Conv1D + FC Layer
//
// IMPORTANT: All negative localparams use  -32'sd25  syntax (minus BEFORE size).
//            NOT 32'sd-25 which is invalid Verilog and parsed as 0 by Vivado.
//
// Pipeline depth = 13 stages (matches controller_fsm val_pipe[12])
//==============================================================================
module conv1d_engine (
    input  wire                 clk,
    input  wire                 reset,
    input  wire                 enable,
    input  wire                 clear_acc,
    input  wire        [119:0]  window_data,
    input  wire        [1919:0] filter_weights,
    output wire signed [23:0]   conv_sum
);

    // ------------------------------------------------------------------
    // BN biases - VERIFIED SYNTAX: minus sign BEFORE the size prefix
    // ------------------------------------------------------------------
    localparam signed [31:0] BN_BIAS_00 = -32'sd25;
    localparam signed [31:0] BN_BIAS_01 =  32'sd5489;
    localparam signed [31:0] BN_BIAS_02 = -32'sd5264;
    localparam signed [31:0] BN_BIAS_03 =  32'sd651;
    localparam signed [31:0] BN_BIAS_04 = -32'sd49;
    localparam signed [31:0] BN_BIAS_05 = -32'sd537;
    localparam signed [31:0] BN_BIAS_06 = -32'sd865;
    localparam signed [31:0] BN_BIAS_07 =  32'sd2337;
    localparam signed [31:0] BN_BIAS_08 = -32'sd25;
    localparam signed [31:0] BN_BIAS_09 =  32'sd8936;
    localparam signed [31:0] BN_BIAS_10 =  32'sd2602;
    localparam signed [31:0] BN_BIAS_11 =  32'sd4724;
    localparam signed [31:0] BN_BIAS_12 = -32'sd633;
    localparam signed [31:0] BN_BIAS_13 = -32'sd661;
    localparam signed [31:0] BN_BIAS_14 = -32'sd3299;
    localparam signed [31:0] BN_BIAS_15 = -32'sd85;

    // ------------------------------------------------------------------
    // FC weights - VERIFIED SYNTAX
    // ------------------------------------------------------------------
    localparam signed [15:0] FC_W_00 =  16'sd32767;
    localparam signed [15:0] FC_W_01 = -16'sd2743;
    localparam signed [15:0] FC_W_02 =  16'sd1605;
    localparam signed [15:0] FC_W_03 = -16'sd4109;
    localparam signed [15:0] FC_W_04 =  16'sd5523;
    localparam signed [15:0] FC_W_05 = -16'sd4926;
    localparam signed [15:0] FC_W_06 = -16'sd4745;
    localparam signed [15:0] FC_W_07 =  16'sd5638;
    localparam signed [15:0] FC_W_08 = -16'sd1290;
    localparam signed [15:0] FC_W_09 =  16'sd3239;
    localparam signed [15:0] FC_W_10 = -16'sd1939;
    localparam signed [15:0] FC_W_11 = -16'sd4830;
    localparam signed [15:0] FC_W_12 =  16'sd10274;
    localparam signed [15:0] FC_W_13 = -16'sd5113;
    localparam signed [15:0] FC_W_14 =  16'sd6189;
    localparam signed [15:0] FC_W_15 = -16'sd1909;

    // ------------------------------------------------------------------
    // 240 MAC units (stages 1-2 via pe_mac)
    // ------------------------------------------------------------------
    wire signed [15:0] mac_out [0:239];
    genvar i;
    generate
        for (i = 0; i < 240; i = i + 1) begin : mac_array
            pe_mac u_mac (
                .clk       (clk),
                .reset     (reset),
                .enable    (enable),
                .data_in   ($signed(window_data  [((i % 15) * 8) +: 8])),
                .weight_in ($signed(filter_weights[(i * 8) +: 8])),
                .clear_acc (clear_acc),
                .acc_out   (mac_out[i])
            );
        end
    endgenerate

    // ------------------------------------------------------------------
    // Stage 3: stg1 (adder tree 15->8 per filter)
    // ------------------------------------------------------------------
    reg signed [23:0] stg1 [0:127];
    integer f1;
    always @(posedge clk) begin
        if (reset) begin
            for (f1=0;f1<128;f1=f1+1) stg1[f1]<=24'd0;
        end else begin
            for (f1=0;f1<16;f1=f1+1) begin
                stg1[f1*8+0]<={{8{mac_out[f1*15+ 0][15]}},mac_out[f1*15+ 0]}+{{8{mac_out[f1*15+ 1][15]}},mac_out[f1*15+ 1]};
                stg1[f1*8+1]<={{8{mac_out[f1*15+ 2][15]}},mac_out[f1*15+ 2]}+{{8{mac_out[f1*15+ 3][15]}},mac_out[f1*15+ 3]};
                stg1[f1*8+2]<={{8{mac_out[f1*15+ 4][15]}},mac_out[f1*15+ 4]}+{{8{mac_out[f1*15+ 5][15]}},mac_out[f1*15+ 5]};
                stg1[f1*8+3]<={{8{mac_out[f1*15+ 6][15]}},mac_out[f1*15+ 6]}+{{8{mac_out[f1*15+ 7][15]}},mac_out[f1*15+ 7]};
                stg1[f1*8+4]<={{8{mac_out[f1*15+ 8][15]}},mac_out[f1*15+ 8]}+{{8{mac_out[f1*15+ 9][15]}},mac_out[f1*15+ 9]};
                stg1[f1*8+5]<={{8{mac_out[f1*15+10][15]}},mac_out[f1*15+10]}+{{8{mac_out[f1*15+11][15]}},mac_out[f1*15+11]};
                stg1[f1*8+6]<={{8{mac_out[f1*15+12][15]}},mac_out[f1*15+12]}+{{8{mac_out[f1*15+13][15]}},mac_out[f1*15+13]};
                stg1[f1*8+7]<={{8{mac_out[f1*15+14][15]}},mac_out[f1*15+14]};
            end
        end
    end

    // ------------------------------------------------------------------
    // Stages 4-5: stg2 and stg3 in one always block
    // Non-blocking assignments: stg3 reads OLD stg2, giving 2 pipeline stages
    // ------------------------------------------------------------------
    reg signed [23:0] stg2 [0:63];
    reg signed [23:0] stg3 [0:31];
    integer f2, f3;
    always @(posedge clk) begin
        if (reset) begin
            for (f2=0;f2<64;f2=f2+1) stg2[f2]<=24'd0;
            for (f3=0;f3<32;f3=f3+1) stg3[f3]<=24'd0;
        end else begin
            for (f2=0;f2<16;f2=f2+1) begin
                stg2[f2*4+0]<=stg1[f2*8+0]+stg1[f2*8+1];
                stg2[f2*4+1]<=stg1[f2*8+2]+stg1[f2*8+3];
                stg2[f2*4+2]<=stg1[f2*8+4]+stg1[f2*8+5];
                stg2[f2*4+3]<=stg1[f2*8+6]+stg1[f2*8+7];
            end
            for (f3=0;f3<16;f3=f3+1) begin
                stg3[f3*2+0]<=stg2[f3*4+0]+stg2[f3*4+1];
                stg3[f3*2+1]<=stg2[f3*4+2]+stg2[f3*4+3];
            end
        end
    end

    // ------------------------------------------------------------------
    // Stage 6: filter_sum (2->1 per filter)
    // ------------------------------------------------------------------
    reg signed [23:0] filter_sum [0:15];
    integer f4;
    always @(posedge clk) begin
        if (reset) begin for (f4=0;f4<16;f4=f4+1) filter_sum[f4]<=24'd0; end
        else for (f4=0;f4<16;f4=f4+1) filter_sum[f4]<=stg3[f4*2+0]+stg3[f4*2+1];
    end

    // ------------------------------------------------------------------
    // Stage 7: relu_reg (add BN bias + ReLU)
    // ------------------------------------------------------------------
    reg signed [23:0] relu_reg [0:15];
    integer i_relu;
    always @(posedge clk) begin
        if (reset) begin for(i_relu=0;i_relu<16;i_relu=i_relu+1) relu_reg[i_relu]<=24'sd0; end
        else begin
            relu_reg[ 0]<=(($signed(filter_sum[ 0])+BN_BIAS_00)<0)?24'sd0:($signed(filter_sum[ 0])+BN_BIAS_00);
            relu_reg[ 1]<=(($signed(filter_sum[ 1])+BN_BIAS_01)<0)?24'sd0:($signed(filter_sum[ 1])+BN_BIAS_01);
            relu_reg[ 2]<=(($signed(filter_sum[ 2])+BN_BIAS_02)<0)?24'sd0:($signed(filter_sum[ 2])+BN_BIAS_02);
            relu_reg[ 3]<=(($signed(filter_sum[ 3])+BN_BIAS_03)<0)?24'sd0:($signed(filter_sum[ 3])+BN_BIAS_03);
            relu_reg[ 4]<=(($signed(filter_sum[ 4])+BN_BIAS_04)<0)?24'sd0:($signed(filter_sum[ 4])+BN_BIAS_04);
            relu_reg[ 5]<=(($signed(filter_sum[ 5])+BN_BIAS_05)<0)?24'sd0:($signed(filter_sum[ 5])+BN_BIAS_05);
            relu_reg[ 6]<=(($signed(filter_sum[ 6])+BN_BIAS_06)<0)?24'sd0:($signed(filter_sum[ 6])+BN_BIAS_06);
            relu_reg[ 7]<=(($signed(filter_sum[ 7])+BN_BIAS_07)<0)?24'sd0:($signed(filter_sum[ 7])+BN_BIAS_07);
            relu_reg[ 8]<=(($signed(filter_sum[ 8])+BN_BIAS_08)<0)?24'sd0:($signed(filter_sum[ 8])+BN_BIAS_08);
            relu_reg[ 9]<=(($signed(filter_sum[ 9])+BN_BIAS_09)<0)?24'sd0:($signed(filter_sum[ 9])+BN_BIAS_09);
            relu_reg[10]<=(($signed(filter_sum[10])+BN_BIAS_10)<0)?24'sd0:($signed(filter_sum[10])+BN_BIAS_10);
            relu_reg[11]<=(($signed(filter_sum[11])+BN_BIAS_11)<0)?24'sd0:($signed(filter_sum[11])+BN_BIAS_11);
            relu_reg[12]<=(($signed(filter_sum[12])+BN_BIAS_12)<0)?24'sd0:($signed(filter_sum[12])+BN_BIAS_12);
            relu_reg[13]<=(($signed(filter_sum[13])+BN_BIAS_13)<0)?24'sd0:($signed(filter_sum[13])+BN_BIAS_13);
            relu_reg[14]<=(($signed(filter_sum[14])+BN_BIAS_14)<0)?24'sd0:($signed(filter_sum[14])+BN_BIAS_14);
            relu_reg[15]<=(($signed(filter_sum[15])+BN_BIAS_15)<0)?24'sd0:($signed(filter_sum[15])+BN_BIAS_15);
        end
    end

    // ------------------------------------------------------------------
    // Stage 8: weighted_reg (FC multiply)
    // ------------------------------------------------------------------
    (* use_dsp = "yes" *) reg signed [39:0] weighted_reg [0:15];
    integer i_w;
    always @(posedge clk) begin
        if (reset) begin for(i_w=0;i_w<16;i_w=i_w+1) weighted_reg[i_w]<=40'sd0; end
        else begin
            weighted_reg[ 0]<=$signed(relu_reg[ 0])*$signed(FC_W_00);
            weighted_reg[ 1]<=$signed(relu_reg[ 1])*$signed(FC_W_01);
            weighted_reg[ 2]<=$signed(relu_reg[ 2])*$signed(FC_W_02);
            weighted_reg[ 3]<=$signed(relu_reg[ 3])*$signed(FC_W_03);
            weighted_reg[ 4]<=$signed(relu_reg[ 4])*$signed(FC_W_04);
            weighted_reg[ 5]<=$signed(relu_reg[ 5])*$signed(FC_W_05);
            weighted_reg[ 6]<=$signed(relu_reg[ 6])*$signed(FC_W_06);
            weighted_reg[ 7]<=$signed(relu_reg[ 7])*$signed(FC_W_07);
            weighted_reg[ 8]<=$signed(relu_reg[ 8])*$signed(FC_W_08);
            weighted_reg[ 9]<=$signed(relu_reg[ 9])*$signed(FC_W_09);
            weighted_reg[10]<=$signed(relu_reg[10])*$signed(FC_W_10);
            weighted_reg[11]<=$signed(relu_reg[11])*$signed(FC_W_11);
            weighted_reg[12]<=$signed(relu_reg[12])*$signed(FC_W_12);
            weighted_reg[13]<=$signed(relu_reg[13])*$signed(FC_W_13);
            weighted_reg[14]<=$signed(relu_reg[14])*$signed(FC_W_14);
            weighted_reg[15]<=$signed(relu_reg[15])*$signed(FC_W_15);
        end
    end

    // ------------------------------------------------------------------
    // Stages 9-12: gt tree + final_total in one always block
    // (4 registers, each reads OLD value of next = 4 pipeline stages)
    // ------------------------------------------------------------------
    reg signed [39:0] gt_stg1 [0:7];
    reg signed [39:0] gt_stg2 [0:3];
    reg signed [39:0] gt_stg3 [0:1];
    reg signed [39:0] final_total;
    integer g1, g2;
    always @(posedge clk) begin
        if (reset) begin
            for(g1=0;g1<8;g1=g1+1) gt_stg1[g1]<=40'd0;
            for(g2=0;g2<4;g2=g2+1) gt_stg2[g2]<=40'd0;
            gt_stg3[0]<=40'd0; gt_stg3[1]<=40'd0;
            final_total<=40'd0;
        end else begin
            gt_stg1[0]<=weighted_reg[ 0]+weighted_reg[ 1];
            gt_stg1[1]<=weighted_reg[ 2]+weighted_reg[ 3];
            gt_stg1[2]<=weighted_reg[ 4]+weighted_reg[ 5];
            gt_stg1[3]<=weighted_reg[ 6]+weighted_reg[ 7];
            gt_stg1[4]<=weighted_reg[ 8]+weighted_reg[ 9];
            gt_stg1[5]<=weighted_reg[10]+weighted_reg[11];
            gt_stg1[6]<=weighted_reg[12]+weighted_reg[13];
            gt_stg1[7]<=weighted_reg[14]+weighted_reg[15];
            gt_stg2[0]<=gt_stg1[0]+gt_stg1[1];
            gt_stg2[1]<=gt_stg1[2]+gt_stg1[3];
            gt_stg2[2]<=gt_stg1[4]+gt_stg1[5];
            gt_stg2[3]<=gt_stg1[6]+gt_stg1[7];
            gt_stg3[0]<=gt_stg2[0]+gt_stg2[1];
            gt_stg3[1]<=gt_stg2[2]+gt_stg2[3];
            final_total<=gt_stg3[0]+gt_stg3[1];
        end
    end

    // ------------------------------------------------------------------
    // Stage 13: shift right 10, clamp, register output
    // ------------------------------------------------------------------
    wire signed [39:0] shifted = $signed(final_total) >>> 10;
    reg signed [23:0] conv_sum_reg;
    always @(posedge clk) begin
        if (reset) conv_sum_reg<=24'd0;
        else begin
            if      (shifted >  40'sd8388607)  conv_sum_reg <=  24'sd8388607;
            else if (shifted < -40'sd8388608)  conv_sum_reg <= -24'sd8388608;
            else                               conv_sum_reg <= shifted[23:0];
        end
    end

    assign conv_sum = conv_sum_reg;

endmodule