`timescale 1ns / 1ps

module OFIFO #(
    parameter DEPTH = 4,
    parameter CHANNELS = 16
)(
    input               s_clk,
    input               s_rst_n,
    input               s_valid,
    output              s_ready,

    input [31:0]        s_id,
    input [31:0]        s_timestamp,
    input [$clog2(CHANNELS)-1:0] s_channel_id,
    input signed [15:0] s_sample,
    output              s_nonempty,

    input               m_clk,
    input               m_rst_n,
    output              m_valid,
    input               m_ready,
    
    output [31:0]       m_id,
    output [31:0]       m_timestamp,
    output [$clog2(CHANNELS)-1:0] m_channel_id,
    output signed [15:0] m_sample
);

localparam CHANNEL_WIDTH = $clog2(CHANNELS);
localparam PACKET_WIDTH  = 32 + 32 + CHANNEL_WIDTH + 16;

wire [PACKET_WIDTH-1:0] s_packet;
wire [PACKET_WIDTH-1:0] m_packet;

assign s_packet = {s_id, s_timestamp, s_channel_id, s_sample};

assign m_id         = m_packet[48+CHANNEL_WIDTH +: 32];
assign m_timestamp  = m_packet[16+CHANNEL_WIDTH +: 32];
assign m_channel_id = m_packet[16 +: CHANNEL_WIDTH];
assign m_sample     = m_packet[15:0];

AFIFO #(
    .DW(PACKET_WIDTH),
    .DEPTH(DEPTH)
) u_OFIFO (
    .s_clk(s_clk),
    .s_rst_n(s_rst_n),
    .s_valid(s_valid),
    .s_ready(s_ready),
    .s_data(s_packet),
    .s_nonempty(s_nonempty),

    .m_clk(m_clk),
    .m_rst_n(m_rst_n),
    .m_valid(m_valid),
    .m_ready(m_ready),
    .m_data(m_packet)
);

endmodule
