`timescale 1ns / 1ps

module AFIFO #(
    parameter DW = 32,
    parameter DEPTH = 16
)(
    input           s_clk,
    input           s_rst_n,
    input           s_valid,
    output          s_ready,
    input  [DW-1:0] s_data,
    output          s_nonempty,

    input           m_clk,
    input           m_rst_n,
    output          m_valid,
    input           m_ready,
    output [DW-1:0] m_data
);

localparam ADDR_WIDTH = $clog2(DEPTH);

reg [DW-1:0] mem [0:DEPTH-1];

reg [ADDR_WIDTH:0] wptr;
reg [ADDR_WIDTH:0] rptr;

reg [ADDR_WIDTH:0] wg;
reg [ADDR_WIDTH:0] rg;

(* ASYNC_REG = "TRUE" *) reg [ADDR_WIDTH:0] wg1, wg2;
(* ASYNC_REG = "TRUE" *) reg [ADDR_WIDTH:0] rg1, rg2;

wire [ADDR_WIDTH:0] wptr_n;
wire [ADDR_WIDTH:0] rptr_n;
wire [ADDR_WIDTH:0] wg_n;
wire [ADDR_WIDTH:0] rg_n;

wire w_hs;
wire r_hs;
wire full;
wire empty;

assign w_hs = s_valid & s_ready;
assign r_hs = m_valid & m_ready;

assign wptr_n = wptr + 1'b1;
assign rptr_n = rptr + 1'b1;

assign wg_n = (wptr_n >> 1) ^ wptr_n;
assign rg_n = (rptr_n >> 1) ^ rptr_n;

assign full  = (wg == {~rg2[ADDR_WIDTH:ADDR_WIDTH-1],
                       rg2[ADDR_WIDTH-2:0]});
assign empty = (rg == wg2);

assign s_ready = ~full;
assign s_nonempty = (wg != rg2);
assign m_valid = ~empty;

assign m_data = mem[rptr[ADDR_WIDTH-1:0]];

// memory write
always @(posedge s_clk) begin
    if (w_hs)
        mem[wptr[ADDR_WIDTH-1:0]] <= s_data;
end

// write pointer
always @(posedge s_clk or negedge s_rst_n) begin
    if (!s_rst_n) begin
        wptr     <= 0;
        wg       <= 0;
    end else if (w_hs) begin
        wptr <= wptr_n;
        wg   <= wg_n;
    end
end

// read
always @(posedge m_clk or negedge m_rst_n) begin
    if (!m_rst_n) begin
        rptr      <= 0;
        rg        <= 0;
    end else begin
        if (r_hs) begin
            rptr <= rptr_n;
            rg   <= rg_n;
        end
    end
end

always @(posedge s_clk or negedge s_rst_n) begin
    if (!s_rst_n) begin
        rg1 <= 0;
        rg2 <= 0;
    end else begin
        rg1 <= rg;
        rg2 <= rg1;
    end
end

always @(posedge m_clk or negedge m_rst_n) begin
    if (!m_rst_n) begin
        wg1 <= 0;
        wg2 <= 0;
    end else begin
        wg1 <= wg;
        wg2 <= wg1;
    end
end

endmodule
