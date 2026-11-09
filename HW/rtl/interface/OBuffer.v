`timescale 1ns/1ps

// SFE clock -> DMA clock result buffer.
// One 512-bit event record is serialized into eight 64-bit WDMA beats.
module OBuffer #(
    parameter DEPTH = 8
)(
    input  wire         s_clk,
    input  wire         s_rst_n,
    input  wire         s_valid,
    input  wire [511:0] s_data,

    input  wire         m_clk,
    input  wire         m_rst_n,
    output wire         event_valid,
    input  wire         event_start,
    output wire [63:0]  m_data,
    output wire         m_valid,
    input  wire         m_ready,
    output wire         empty,

    // One m_clk pulse whenever an SFE result arrives while the FIFO is full.
    output wire         overflow
);

wire         fifo_m_valid;
wire         fifo_m_ready;
wire [511:0] fifo_m_data;
wire         fifo_s_ready;
wire         m_hs;
wire         unused_s_nonempty;

reg [511:0] shift_data;
reg [2:0]   word_index;
reg         active;

reg overflow_toggle_s;
(* ASYNC_REG = "TRUE" *) reg overflow_sync1_m;
(* ASYNC_REG = "TRUE" *) reg overflow_sync2_m;
reg overflow_sync2_d_m;

assign event_valid = fifo_m_valid && !active;
assign fifo_m_ready = event_start && event_valid;

assign m_data      = shift_data[63:0];
assign m_valid     = active;
assign m_hs        = m_valid && m_ready;
assign empty       = !fifo_m_valid && !active;
assign overflow    = overflow_sync2_m ^ overflow_sync2_d_m;

AFIFO #(
    .DW(512),
    .DEPTH(DEPTH)
) u_result_fifo (
    .s_clk(s_clk),
    .s_rst_n(s_rst_n),
    .s_valid(s_valid),
    .s_ready(fifo_s_ready),
    .s_data(s_data),
    .s_nonempty(unused_s_nonempty),

    .m_clk(m_clk),
    .m_rst_n(m_rst_n),
    .m_valid(fifo_m_valid),
    .m_ready(fifo_m_ready),
    .m_data(fifo_m_data)
);

always @(posedge s_clk or negedge s_rst_n) begin
    if (!s_rst_n)
        overflow_toggle_s <= 1'b0;
    else if (s_valid && !fifo_s_ready)
        overflow_toggle_s <= ~overflow_toggle_s;
end

always @(posedge m_clk or negedge m_rst_n) begin
    if (!m_rst_n) begin
        overflow_sync1_m   <= 1'b0;
        overflow_sync2_m   <= 1'b0;
        overflow_sync2_d_m <= 1'b0;
    end else begin
        overflow_sync1_m   <= overflow_toggle_s;
        overflow_sync2_m   <= overflow_sync1_m;
        overflow_sync2_d_m <= overflow_sync2_m;
    end
end

always @(posedge m_clk or negedge m_rst_n) begin
    if (!m_rst_n) begin
        shift_data <= 512'd0;
        word_index <= 3'd0;
        active     <= 1'b0;
    end else begin
        if (fifo_m_ready && fifo_m_valid) begin
            shift_data <= fifo_m_data;
            word_index <= 3'd0;
            active     <= 1'b1;
        end else if (m_hs) begin
            if (word_index == 3'd7) begin
                word_index <= 3'd0;
                active     <= 1'b0;
            end else begin
                shift_data <= {64'd0, shift_data[511:64]};
                word_index <= word_index + 1'b1;
            end
        end
    end
end

endmodule
