`timescale 1ns / 1ps

module WindowFIFO #(
    parameter DEPTH = 64
)(
    input               s_clk,
    input               s_rst_n,
    input               s_valid,
    output              s_ready,
    input signed [15:0] s_sample,

    input               m_clk,
    input               m_rst_n,
    output              m_valid,
    input               m_ready,
    output signed [15:0] m_sample
);

wire unused_s_nonempty;

AFIFO #(
    .DW(16),
    .DEPTH(DEPTH)
) u_WindowFIFO (
    .s_clk(s_clk),
    .s_rst_n(s_rst_n),
    .s_valid(s_valid),
    .s_ready(s_ready),
    .s_data(s_sample),
    .s_nonempty(unused_s_nonempty),

    .m_clk(m_clk),
    .m_rst_n(m_rst_n),
    .m_valid(m_valid),
    .m_ready(m_ready),
    .m_data(m_sample)
);

endmodule
