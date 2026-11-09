`timescale 1ns/1ps

// DMA clock -> neural sample clock buffer.
// The final-input marker travels with the 64-bit sample.
module IBuffer #(
    parameter DEPTH = 32
)(
    input  wire        s_clk,
    input  wire        s_rst_n,
    input  wire        s_valid,
    output wire        s_ready,
    input  wire [63:0] s_data,
    input  wire        s_last,

    input  wire        m_clk,
    input  wire        m_rst_n,
    output wire        m_valid,
    input  wire        m_ready,
    output wire [63:0] m_data,
    output wire        m_last,

    // One s_clk pulse after the final sample leaves this buffer.
    output wire        drain_done
);

wire [64:0] fifo_s_data;
wire [64:0] fifo_m_data;
wire        m_hs;
wire        unused_s_nonempty;

reg last_toggle_m;
reg last_pending_m;
(* ASYNC_REG = "TRUE" *) reg last_sync1_s;
(* ASYNC_REG = "TRUE" *) reg last_sync2_s;
reg last_sync2_d_s;

assign fifo_s_data = {s_last, s_data};
assign m_last      = fifo_m_data[64];
assign m_data      = fifo_m_data[63:0];
assign m_hs        = m_valid && m_ready;
assign drain_done  = last_sync2_s ^ last_sync2_d_s;

AFIFO #(
    .DW(65),
    .DEPTH(DEPTH)
) u_data_fifo (
    .s_clk(s_clk),
    .s_rst_n(s_rst_n),
    .s_valid(s_valid),
    .s_ready(s_ready),
    .s_data(fifo_s_data),
    .s_nonempty(unused_s_nonempty),

    .m_clk(m_clk),
    .m_rst_n(m_rst_n),
    .m_valid(m_valid),
    .m_ready(m_ready),
    .m_data(fifo_m_data)
);

always @(posedge m_clk or negedge m_rst_n) begin
    if (!m_rst_n) begin
        last_toggle_m  <= 1'b0;
        last_pending_m <= 1'b0;
    end else if (last_pending_m) begin
        // Wait one sample clock so the final word is visible inside MainPath.
        last_toggle_m  <= ~last_toggle_m;
        last_pending_m <= 1'b0;
    end else if (m_hs && m_last) begin
        last_pending_m <= 1'b1;
    end
end

always @(posedge s_clk or negedge s_rst_n) begin
    if (!s_rst_n) begin
        last_sync1_s   <= 1'b0;
        last_sync2_s   <= 1'b0;
        last_sync2_d_s <= 1'b0;
    end else begin
        last_sync1_s   <= last_toggle_m;
        last_sync2_s   <= last_sync1_s;
        last_sync2_d_s <= last_sync2_s;
    end
end

endmodule
