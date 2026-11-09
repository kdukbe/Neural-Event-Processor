`timescale 1ns / 1ps

// Synthesis wrapper for MainPath.
// The wide SFE result is folded into one 32-bit check value so that
// MainPath can be implemented without using hundreds of FPGA I/O pins.
module MainPathSynthWrapper #(
    parameter CHANNELS      = 16,
    parameter IFIFO_DEPTH   = 4,
    parameter WINDOW_DEPTH  = 64,
    parameter OFIFO_DEPTH   = 16,
    parameter WFIFO_DEPTH   = 1024,
    parameter PENDING_DEPTH = 16,
    parameter THRESHOLD     = 15000,
    parameter REFRACTORY    = 63,
    parameter POST_SAMPLES  = 30,
    parameter EVENT_DRIVEN  = 0
)(
    input               s_clk,
    input               s_rst_n,
    input               clk,
    input               rst_n,
    input               sfe_clk,
    input               sfe_rst_n,

    input               i_threshold_valid,
    output              o_threshold_ready,
    input [31:0]        i_threshold_value,

    input               i_cfg_valid,
    output              o_cfg_ready,
    input [$clog2(CHANNELS)-1:0] i_cfg_channel_id,
    input [2:0]         i_cfg_feature_id,
    input signed [6:0]  i_cfg_offset,
    input               i_cfg_enable,

    input               s_valid,
    output              s_ready,
    input [31:0]        s_timestamp,
    input [$clog2(CHANNELS)-1:0] s_channel_id,
    input signed [15:0] s_sample,

    output              o_valid,
    output [31:0]       o_result_check,
    output              o_busy,
    output              o_event_drop,
    output [$clog2(PENDING_DEPTH):0] o_pending_level,
    output              o_sfe_active
);

wire [31:0] main_id;
wire [31:0] main_timestamp;
wire [$clog2(CHANNELS)-1:0] main_channel_id;
wire signed [15:0] main_event_sample;
wire [6:0] main_feature_flag;
wire signed [35:0] main_feature0;
wire signed [35:0] main_feature1;
wire signed [35:0] main_feature2;
wire signed [35:0] main_feature3;
wire signed [35:0] main_feature4;
wire signed [35:0] main_feature5;
wire signed [35:0] main_feature6;
wire [5:0] main_max_slope_index;

wire [31:0] feature_upper_bits;

// Keep every wide result bit in the synthesized design without exposing
// every result as a separate FPGA pin.
assign feature_upper_bits = {
    4'b0,
    main_feature6[35:32],
    main_feature5[35:32],
    main_feature4[35:32],
    main_feature3[35:32],
    main_feature2[35:32],
    main_feature1[35:32],
    main_feature0[35:32]
};

assign o_result_check =
    main_id ^
    main_timestamp ^
    {{(32-$clog2(CHANNELS)){1'b0}}, main_channel_id} ^
    {16'b0, main_event_sample} ^
    {25'b0, main_feature_flag} ^
    main_feature0[31:0] ^
    main_feature1[31:0] ^
    main_feature2[31:0] ^
    main_feature3[31:0] ^
    main_feature4[31:0] ^
    main_feature5[31:0] ^
    main_feature6[31:0] ^
    feature_upper_bits ^
    {26'b0, main_max_slope_index};

MainPath #(
    .CHANNELS(CHANNELS),
    .IFIFO_DEPTH(IFIFO_DEPTH),
    .WINDOW_DEPTH(WINDOW_DEPTH),
    .OFIFO_DEPTH(OFIFO_DEPTH),
    .WFIFO_DEPTH(WFIFO_DEPTH),
    .PENDING_DEPTH(PENDING_DEPTH),
    .THRESHOLD(THRESHOLD),
    .REFRACTORY(REFRACTORY),
    .POST_SAMPLES(POST_SAMPLES),
    .EVENT_DRIVEN(EVENT_DRIVEN)
) u_MainPath (
    .s_valid(s_valid),
    .s_ready(s_ready),
    .s_timestamp(s_timestamp),
    .s_channel_id(s_channel_id),
    .s_sample(s_sample),

    .s_clk(s_clk),
    .s_rst_n(s_rst_n),

    .clk(clk),
    .rst_n(rst_n),
    .sfe_clk(sfe_clk),
    .sfe_rst_n(sfe_rst_n),

    .i_cfg_valid(i_cfg_valid),
    .i_threshold_valid(i_threshold_valid),
    .o_threshold_ready(o_threshold_ready),
    .i_threshold_value(i_threshold_value),
    .o_cfg_ready(o_cfg_ready),
    .i_cfg_channel_id(i_cfg_channel_id),
    .i_cfg_feature_id(i_cfg_feature_id),
    .i_cfg_offset(i_cfg_offset),
    .i_cfg_enable(i_cfg_enable),

    .o_valid(o_valid),
    .o_id(main_id),
    .o_timestamp(main_timestamp),
    .o_channel_id(main_channel_id),
    .o_event_sample(main_event_sample),
    .o_feature_flag(main_feature_flag),
    .o_feature0(main_feature0),
    .o_feature1(main_feature1),
    .o_feature2(main_feature2),
    .o_feature3(main_feature3),
    .o_feature4(main_feature4),
    .o_feature5(main_feature5),
    .o_feature6(main_feature6),
    .o_max_slope_index(main_max_slope_index),
    .o_busy(o_busy),
    .o_event_drop(o_event_drop),
    .o_pending_level(o_pending_level),
    .o_sfe_active(o_sfe_active)
);

endmodule
