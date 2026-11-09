`timescale 1ns / 1ps

module MainPath #(
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
    input               s_valid,
    output              s_ready,
    input [31:0]        s_timestamp,
    input [$clog2(CHANNELS)-1:0] s_channel_id,
    input signed [15:0] s_sample,

    input               s_clk,
    input               s_rst_n,

    input               clk,
    input               rst_n,

    input               sfe_clk,
    input               sfe_rst_n,

    // SD threshold configuration (Main clock, before sample input).
    input               i_threshold_valid,
    output              o_threshold_ready,
    input [31:0]        i_threshold_value,

    // SFE feature configuration (synchronous to sfe_clk).
    input               i_cfg_valid,
    output              o_cfg_ready,
    input [$clog2(CHANNELS)-1:0] i_cfg_channel_id,
    input [2:0]         i_cfg_feature_id,
    input signed [6:0]  i_cfg_offset,
    input               i_cfg_enable,

    output               o_valid,
    output [31:0]        o_id,
    output [31:0]        o_timestamp,
    output [$clog2(CHANNELS)-1:0] o_channel_id,
    output signed [15:0] o_event_sample,
    output [6:0]         o_feature_flag,
    output signed [35:0] o_feature0,
    output signed [35:0] o_feature1,
    output signed [35:0] o_feature2,
    output signed [35:0] o_feature3,
    output signed [35:0] o_feature4,
    output signed [35:0] o_feature5,
    output signed [35:0] o_feature6,
    output [5:0]         o_max_slope_index,
    output               o_busy,
    output               o_event_drop,
    output [$clog2(PENDING_DEPTH):0] o_pending_level,
    output               o_sfe_active
);

localparam WINDOW_ADDR_WIDTH = $clog2(WINDOW_DEPTH);

wire ififo_valid;
wire ififo_ready;
wire [31:0] ififo_timestamp;
wire [$clog2(CHANNELS)-1:0] ififo_channel_id;
wire signed [15:0] ififo_sample;
wire sample_hs;
wire sd_threshold_ready;
assign o_threshold_ready = !o_busy && sd_threshold_ready;

wire sd_valid;
wire [31:0] sd_id;
wire [31:0] sd_timestamp;
wire [$clog2(CHANNELS)-1:0] sd_channel_id;
wire signed [15:0] sd_sample;

wire pending_valid;
wire pending_pop;
wire [31:0] pending_id;
wire [31:0] pending_timestamp;
wire [$clog2(CHANNELS)-1:0] pending_channel_id;
wire signed [15:0] pending_sample;
wire [WINDOW_ADDR_WIDTH-1:0] pending_window_base;
wire pending_window_ready;
wire pending_overflow;

wire read_request;
wire read_ready;
wire [$clog2(CHANNELS)-1:0] read_channel_id;
wire [WINDOW_ADDR_WIDTH-1:0] read_base;
wire [WINDOW_ADDR_WIDTH-1:0] read_index;

wire [WINDOW_ADDR_WIDTH-1:0] event_next_addr;
wire [CHANNELS-1:0] detect_ready;

wire window_valid;
wire window_ready;
wire window_last;
wire signed [15:0] window_sample;

wire controller_event_valid;
wire controller_event_ready;
wire controller_busy;

wire ofifo_valid;
wire ofifo_ready;
wire [31:0] ofifo_id;
wire [31:0] ofifo_timestamp;
wire [$clog2(CHANNELS)-1:0] ofifo_channel_id;
wire signed [15:0] ofifo_sample;

wire wfifo_valid;
wire wfifo_ready;
wire signed [15:0] wfifo_sample;

wire sfe_busy;
wire sfe_run_clk;
wire sfe_cfg_ready;
wire sfe_cfg_valid;
wire ofifo_write_pending;

assign ififo_ready = 1'b1;
assign sample_hs = ififo_valid & ififo_ready;

assign o_event_drop = pending_overflow;
// Busy stays high while any sample, event, or result is still inside MainPath.
assign o_busy = ififo_valid |
                (o_pending_level != 0) |
                controller_busy |
                ofifo_write_pending |
                ofifo_valid |
                wfifo_valid |
                sfe_busy |
                o_valid;

IFIFO #(
    .DEPTH(IFIFO_DEPTH),
    .CHANNELS(CHANNELS)
) u_IFIFO (
    .s_clk(s_clk),
    .s_rst_n(s_rst_n),
    .s_valid(s_valid),
    .s_ready(s_ready),
    .s_timestamp(s_timestamp),
    .s_channel_id(s_channel_id),
    .s_sample(s_sample),

    .m_clk(clk),
    .m_rst_n(rst_n),
    .m_valid(ififo_valid),
    .m_ready(ififo_ready),
    .m_timestamp(ififo_timestamp),
    .m_channel_id(ififo_channel_id),
    .m_sample(ififo_sample)
);

SD #(
    .CHANNELS(CHANNELS),
    .threshold(THRESHOLD),
    .refractory(REFRACTORY)
) u_SD (
    .clk(clk),
    .rst_n(rst_n),
    .i_enable(detect_ready[ififo_channel_id]),
    .i_threshold_valid(i_threshold_valid && !o_busy),
    .o_threshold_ready(sd_threshold_ready),
    .i_threshold_value(i_threshold_value),
    .i_valid(sample_hs),
    .i_timestamp(ififo_timestamp),
    .i_channel_id(ififo_channel_id),
    .i_sample(ififo_sample),
    .o_valid(sd_valid),
    .o_id(sd_id),
    .o_timestamp(sd_timestamp),
    .o_channel_id(sd_channel_id),
    .o_sample(sd_sample)
);

WindowBuffer #(
    .CHANNELS(CHANNELS),
    .DEPTH(WINDOW_DEPTH)
) u_WindowBuffer (
    .clk(clk),
    .rst_n(rst_n),
    .i_valid(sample_hs),
    .i_channel_id(ififo_channel_id),
    .i_sample(ififo_sample),

    .o_detect_ready(detect_ready),
    .i_event_channel_id(sd_channel_id),
    .o_event_next_addr(event_next_addr),

    .i_read(read_request),
    .o_read_ready(read_ready),
    .i_read_channel_id(read_channel_id),
    .i_read_base(read_base),
    .i_read_index(read_index),

    .o_valid(window_valid),
    .i_ready(window_ready),
    .o_last(window_last),
    .o_sample(window_sample)
);

PendingEventQueue #(
    .CHANNELS(CHANNELS),
    .WINDOW_DEPTH(WINDOW_DEPTH),
    .DEPTH(PENDING_DEPTH),
    .POST_SAMPLES(POST_SAMPLES)
) u_PendingEventQueue (
    .clk(clk),
    .rst_n(rst_n),
    .i_sample_valid(sample_hs),
    .i_sample_channel_id(ififo_channel_id),
    .i_event_next_addr(event_next_addr),

    .i_event_valid(sd_valid),
    .i_event_id(sd_id),
    .i_event_timestamp(sd_timestamp),
    .i_event_channel_id(sd_channel_id),
    .i_event_sample(sd_sample),

    .o_valid(pending_valid),
    .i_pop(pending_pop),
    .o_id(pending_id),
    .o_timestamp(pending_timestamp),
    .o_channel_id(pending_channel_id),
    .o_sample(pending_sample),
    .o_window_base(pending_window_base),
    .o_window_ready(pending_window_ready),
    .o_overflow(pending_overflow),
    .o_level(o_pending_level)
);

WindowController #(
    .CHANNELS(CHANNELS),
    .DEPTH(WINDOW_DEPTH)
) u_WindowController (
    .clk(clk),
    .rst_n(rst_n),

    .i_pending_valid(pending_valid),
    .i_pending_window_ready(pending_window_ready),
    .o_pending_pop(pending_pop),
    .i_pending_channel_id(pending_channel_id),
    .i_pending_window_base(pending_window_base),

    .i_read_ready(read_ready),
    .i_window_valid(window_valid),
    .i_window_last(window_last),
    .i_window_ready(window_ready),

    .o_read(read_request),
    .o_read_channel_id(read_channel_id),
    .o_read_base(read_base),
    .o_read_index(read_index),

    .o_event_valid(controller_event_valid),
    .i_event_ready(controller_event_ready),
    .o_busy(controller_busy)
);

WindowFIFO #(
    .DEPTH(WFIFO_DEPTH)
) u_WindowFIFO (
    .s_clk(clk),
    .s_rst_n(rst_n),
    .s_valid(window_valid),
    .s_ready(window_ready),
    .s_sample(window_sample),

    .m_clk(sfe_run_clk),
    .m_rst_n(sfe_rst_n),
    .m_valid(wfifo_valid),
    .m_ready(wfifo_ready),
    .m_sample(wfifo_sample)
);

OFIFO #(
    .DEPTH(OFIFO_DEPTH),
    .CHANNELS(CHANNELS)
) u_OFIFO (
    .s_clk(clk),
    .s_rst_n(rst_n),
    .s_valid(controller_event_valid),
    .s_ready(controller_event_ready),
    .s_id(pending_id),
    .s_timestamp(pending_timestamp),
    .s_channel_id(pending_channel_id),
    .s_sample(pending_sample),
    .s_nonempty(ofifo_write_pending),

    .m_clk(sfe_run_clk),
    .m_rst_n(sfe_rst_n),
    .m_valid(ofifo_valid),
    .m_ready(ofifo_ready),
    .m_id(ofifo_id),
    .m_timestamp(ofifo_timestamp),
    .m_channel_id(ofifo_channel_id),
    .m_sample(ofifo_sample)
);

generate
    if (EVENT_DRIVEN) begin : g_event_driven
        SFEClockControl u_SFEClockControl (
            .base_clk(sfe_clk),
            .rst_n(sfe_rst_n),
            .work_pending_main(ofifo_write_pending),
            .cfg_valid(i_cfg_valid),
            .sfe_busy(sfe_busy),
            .result_valid(o_valid),
            .run_clk(sfe_run_clk),
            .active(o_sfe_active)
        );

        // The raw-clock configuration FIFO must not consume a setting until
        // the gated SFE clock is running and can capture the same handshake.
        assign o_cfg_ready   = o_sfe_active && sfe_cfg_ready;
        assign sfe_cfg_valid = o_sfe_active && i_cfg_valid;
    end else begin : g_always_on
        assign sfe_run_clk   = sfe_clk;
        assign o_sfe_active  = 1'b1;
        assign o_cfg_ready   = sfe_cfg_ready;
        assign sfe_cfg_valid = i_cfg_valid;
    end
endgenerate

SFE #(
    .CHANNELS(CHANNELS)
) u_SFE (
    .clk(sfe_run_clk),
    .rst_n(sfe_rst_n),

    .i_cfg_valid(sfe_cfg_valid),
    .o_cfg_ready(sfe_cfg_ready),
    .i_cfg_channel_id(i_cfg_channel_id),
    .i_cfg_feature_id(i_cfg_feature_id),
    .i_cfg_offset(i_cfg_offset),
    .i_cfg_enable(i_cfg_enable),

    .i_event_valid(ofifo_valid),
    .i_event_ready(ofifo_ready),
    .i_event_id(ofifo_id),
    .i_event_timestamp(ofifo_timestamp),
    .i_event_channel_id(ofifo_channel_id),
    .i_event_sample(ofifo_sample),

    .i_sample_valid(wfifo_valid),
    .i_sample_ready(wfifo_ready),
    .i_sample(wfifo_sample),

    .o_valid(o_valid),
    .o_id(o_id),
    .o_timestamp(o_timestamp),
    .o_channel_id(o_channel_id),
    .o_event_sample(o_event_sample),
    .o_feature_flag(o_feature_flag),
    .o_feature0(o_feature0),
    .o_feature1(o_feature1),
    .o_feature2(o_feature2),
    .o_feature3(o_feature3),
    .o_feature4(o_feature4),
    .o_feature5(o_feature5),
    .o_feature6(o_feature6),
    .o_max_slope_index(o_max_slope_index),
    .o_busy(sfe_busy)
);

endmodule
