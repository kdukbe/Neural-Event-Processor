`timescale 1ns / 1ps

module SD #(
    parameter CHANNELS   = 16,
    parameter threshold  = 15000,
    parameter refractory = 63
)(
    input               clk,
    input               rst_n,
    input               i_enable,

    // Main clock: set one shared threshold before sending samples.
    input               i_threshold_valid,
    output              o_threshold_ready,
    input [31:0]        i_threshold_value,

    input               i_valid,
    input [31:0]        i_timestamp,
    input [$clog2(CHANNELS)-1:0] i_channel_id,
    input signed [15:0] i_sample,

    output reg          o_valid,
    output reg [31:0]   o_id,
    output reg [31:0]   o_timestamp,
    output reg [$clog2(CHANNELS)-1:0] o_channel_id,
    output reg signed [15:0] o_sample
);

wire signed [15:0] old_sample [0:CHANNELS-1];
wire signed [15:0] mid_sample [0:CHANNELS-1];
wire [31:0] mid_timestamp [0:CHANNELS-1];
wire [CHANNELS-1:0] enough_samples;

genvar channel;
generate
    for (channel = 0; channel < CHANNELS; channel = channel + 1) begin : g_channel_rb
        SD_RB u_SD_RB (
            .clk(clk),
            .rst_n(rst_n),
            .write_en(i_valid && (i_channel_id == channel)),
            .i_timestamp(i_timestamp),
            .i_sample(i_sample),
            .old_sample(old_sample[channel]),
            .mid_sample(mid_sample[channel]),
            .mid_timestamp(mid_timestamp[channel]),
            .enough_samples(enough_samples[channel])
        );
    end
endgenerate

reg signed [15:0] mux_old;
reg signed [15:0] mux_mid;
reg [31:0] mux_mid_timestamp;
reg mux_enough;

reg [7:0] refractory_count [0:CHANNELS-1];
reg mux_refractory;

always @(*) begin
    mux_old           = 0;
    mux_mid           = 0;
    mux_mid_timestamp = 0;
    mux_enough        = 1'b0;
    mux_refractory    = 1'b1;

    if (i_channel_id < CHANNELS) begin
        mux_old           = old_sample[i_channel_id];
        mux_mid           = mid_sample[i_channel_id];
        mux_mid_timestamp = mid_timestamp[i_channel_id];
        mux_enough        = enough_samples[i_channel_id];
        mux_refractory    = (refractory_count[i_channel_id] != 0);
    end
end

wire signed [31:0] mid_square;
wire signed [31:0] side_product;
wire signed [32:0] neo_value;
wire threshold_hit;
wire spike_hit;

reg [31:0] threshold_reg;
assign o_threshold_ready = !i_valid;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        threshold_reg <= threshold;
    end else if (i_threshold_valid && o_threshold_ready) begin
        threshold_reg <= i_threshold_value;
    end
end

assign mid_square   = mux_mid * mux_mid;
assign side_product = mux_old * i_sample;
assign neo_value    = $signed({mid_square[31], mid_square}) - $signed({side_product[31], side_product});
// Extend the unsigned threshold before comparing it with the signed NEO.
assign threshold_hit = (neo_value >= $signed({1'b0, threshold_reg}));

assign spike_hit = i_valid && i_enable && mux_enough && threshold_hit && !mux_refractory;

integer ref_i;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for (ref_i = 0; ref_i < CHANNELS; ref_i = ref_i + 1)
            refractory_count[ref_i] <= 0;
    end else if (i_valid && (i_channel_id < CHANNELS)) begin
        if (spike_hit)
            refractory_count[i_channel_id] <= refractory;
        else if (refractory_count[i_channel_id] != 0)
            refractory_count[i_channel_id] <= refractory_count[i_channel_id] - 1'b1;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        o_valid      <= 1'b0;
        o_id         <= 0;
        o_timestamp  <= 0;
        o_channel_id <= 0;
        o_sample     <= 0;
    end else begin
        o_valid <= 1'b0;

        if (spike_hit) begin
            o_valid      <= 1'b1;
            o_id         <= o_id + 1'b1;
            o_timestamp  <= mux_mid_timestamp;
            o_channel_id <= i_channel_id;
            o_sample     <= mux_mid;
        end
    end
end

endmodule
