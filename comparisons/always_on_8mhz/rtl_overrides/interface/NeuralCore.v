`timescale 1ns/1ps

// Research-core boundary: IFIFO through SFE.
module NeuralCore #(
    parameter CHANNELS      = 16,
    parameter IFIFO_DEPTH   = 4,
    parameter WINDOW_DEPTH  = 64,
    parameter OFIFO_DEPTH   = 8,
    parameter WFIFO_DEPTH   = 512,
    parameter PENDING_DEPTH = 16,
    parameter THRESHOLD     = 15000,
    parameter REFRACTORY    = 63,
    parameter POST_SAMPLES  = 30,
    parameter EVENT_DRIVEN  = 0
)(
    // Neural sample input
    input  wire                              s_clk,
    input  wire                              s_rst_n,
    input  wire                              s_valid,
    output wire                              s_ready,
    input  wire [31:0]                       s_timestamp,
    input  wire [$clog2(CHANNELS)-1:0]       s_channel_id,
    input  wire signed [15:0]                s_sample,

    // Main processing clock
    input  wire                              main_clk,
    input  wire                              main_rst_n,

    // SD threshold settings use main_clk.
    input  wire                              threshold_valid,
    output wire                              threshold_ready,
    input  wire [31:0]                       threshold_value,

    // SFE clock and configuration
    input  wire                              sfe_clk,
    input  wire                              sfe_rst_n,
    input  wire                              cfg_valid,
    output wire                              cfg_ready,
    input  wire [$clog2(CHANNELS)-1:0]       cfg_channel_id,
    input  wire [2:0]                        cfg_feature_id,
    input  wire signed [6:0]                 cfg_offset,
    input  wire                              cfg_enable,

    // One fixed-size record per detected event
    output wire                              result_valid,
    output wire [511:0]                      result_data,

    // Status
    output wire                              busy,
    output wire                              event_drop,
    output wire [$clog2(PENDING_DEPTH):0]    pending_level,
    output wire                              sfe_active
);

localparam CHANNEL_WIDTH = $clog2(CHANNELS);
localparam RESULT_USED_WIDTH = 345 + CHANNEL_WIDTH;

wire [31:0]             result_id;
wire [31:0]             result_timestamp;
wire [CHANNEL_WIDTH-1:0] result_channel;
wire signed [15:0]      result_event_sample;
wire [6:0]              result_feature_flag;
wire signed [35:0]      result_feature0;
wire signed [35:0]      result_feature1;
wire signed [35:0]      result_feature2;
wire signed [35:0]      result_feature3;
wire signed [35:0]      result_feature4;
wire signed [35:0]      result_feature5;
wire signed [35:0]      result_feature6;
wire [5:0]              result_slope_index;

// Bits [348:0] are used for CHANNELS=16. The remaining upper bits are zero.
assign result_data = {
    {(512-RESULT_USED_WIDTH){1'b0}},
    result_feature6,
    result_feature5,
    result_feature4,
    result_feature3,
    result_feature2,
    result_feature1,
    result_feature0,
    result_slope_index,
    result_feature_flag,
    result_event_sample,
    result_channel,
    result_timestamp,
    result_id
};

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
    .clk(main_clk),
    .rst_n(main_rst_n),
    .sfe_clk(sfe_clk),
    .sfe_rst_n(sfe_rst_n),

    .i_cfg_valid(cfg_valid),
    .i_threshold_valid(threshold_valid),
    .o_threshold_ready(threshold_ready),
    .i_threshold_value(threshold_value),
    .o_cfg_ready(cfg_ready),
    .i_cfg_channel_id(cfg_channel_id),
    .i_cfg_feature_id(cfg_feature_id),
    .i_cfg_offset(cfg_offset),
    .i_cfg_enable(cfg_enable),

    .o_valid(result_valid),
    .o_id(result_id),
    .o_timestamp(result_timestamp),
    .o_channel_id(result_channel),
    .o_event_sample(result_event_sample),
    .o_feature_flag(result_feature_flag),
    .o_feature0(result_feature0),
    .o_feature1(result_feature1),
    .o_feature2(result_feature2),
    .o_feature3(result_feature3),
    .o_feature4(result_feature4),
    .o_feature5(result_feature5),
    .o_feature6(result_feature6),
    .o_max_slope_index(result_slope_index),
    .o_busy(busy),
    .o_event_drop(event_drop),
    .o_pending_level(pending_level),
    .o_sfe_active(sfe_active)
);

endmodule
