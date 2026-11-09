`timescale 1ns/1ps

module top #(
    parameter ID_WIDTH       = 6,
    parameter CHANNELS       = 16,
    parameter IFIFO_DEPTH    = 4,
    parameter WINDOW_DEPTH   = 64,
    parameter OFIFO_DEPTH    = 16,
    parameter WFIFO_DEPTH    = 1024,
    parameter PENDING_DEPTH  = 16,
    parameter IBUFFER_DEPTH  = 32,
    parameter OBUFFER_DEPTH  = 8,
    parameter THRESHOLD      = 15000,
    parameter REFRACTORY     = 63,
    parameter POST_SAMPLES   = 30,
    parameter EVENT_DRIVEN   = 0
)(
    // Clocks and resets
    input  wire                    AXI_CLK,
    input  wire                    AXI_RSTN,
    input  wire                    SAMPLE_CLK,
    input  wire                    SAMPLE_RSTN,
    input  wire                    MAIN_CLK,
    input  wire                    MAIN_RSTN,
    input  wire                    SFE_CLK,
    input  wire                    SFE_RSTN,

    // AXI4-Lite slave: configuration and status
    input  wire [31:0]             S_AXI_AWADDR,
    input  wire [2:0]              S_AXI_AWPROT,
    input  wire                    S_AXI_AWVALID,
    output wire                    S_AXI_AWREADY,
    input  wire [31:0]             S_AXI_WDATA,
    input  wire [3:0]              S_AXI_WSTRB,
    input  wire                    S_AXI_WVALID,
    output wire                    S_AXI_WREADY,
    output wire [1:0]              S_AXI_BRESP,
    output wire                    S_AXI_BVALID,
    input  wire                    S_AXI_BREADY,
    input  wire [31:0]             S_AXI_ARADDR,
    input  wire [2:0]              S_AXI_ARPROT,
    input  wire                    S_AXI_ARVALID,
    output wire                    S_AXI_ARREADY,
    output wire [31:0]             S_AXI_RDATA,
    output wire [1:0]              S_AXI_RRESP,
    output wire                    S_AXI_RVALID,
    input  wire                    S_AXI_RREADY,

    // AXI4-Full master write address channel
    output wire [ID_WIDTH-1:0]     M_AXI_AWID,
    output wire [31:0]             M_AXI_AWADDR,
    output wire [7:0]              M_AXI_AWLEN,
    output wire [2:0]              M_AXI_AWSIZE,
    output wire [1:0]              M_AXI_AWBURST,
    output wire                    M_AXI_AWLOCK,
    output wire [3:0]              M_AXI_AWCACHE,
    output wire [2:0]              M_AXI_AWPROT,
    output wire [3:0]              M_AXI_AWQOS,
    output wire                    M_AXI_AWVALID,
    input  wire                    M_AXI_AWREADY,

    // AXI4-Full master write data channel
    output wire [63:0]             M_AXI_WDATA,
    output wire [7:0]              M_AXI_WSTRB,
    output wire                    M_AXI_WLAST,
    output wire                    M_AXI_WVALID,
    input  wire                    M_AXI_WREADY,

    // AXI4-Full master write response channel
    input  wire [ID_WIDTH-1:0]     M_AXI_BID,
    input  wire [1:0]              M_AXI_BRESP,
    input  wire                    M_AXI_BVALID,
    output wire                    M_AXI_BREADY,

    // AXI4-Full master read address channel
    output wire [ID_WIDTH-1:0]     M_AXI_ARID,
    output wire [31:0]             M_AXI_ARADDR,
    output wire [7:0]              M_AXI_ARLEN,
    output wire [2:0]              M_AXI_ARSIZE,
    output wire [1:0]              M_AXI_ARBURST,
    output wire                    M_AXI_ARLOCK,
    output wire [3:0]              M_AXI_ARCACHE,
    output wire [2:0]              M_AXI_ARPROT,
    output wire [3:0]              M_AXI_ARQOS,
    output wire                    M_AXI_ARVALID,
    input  wire                    M_AXI_ARREADY,

    // AXI4-Full master read data channel
    input  wire [ID_WIDTH-1:0]     M_AXI_RID,
    input  wire [63:0]             M_AXI_RDATA,
    input  wire [1:0]              M_AXI_RRESP,
    input  wire                    M_AXI_RLAST,
    input  wire                    M_AXI_RVALID,
    output wire                    M_AXI_RREADY,

    output wire                    IRQ
);

localparam CHANNEL_WIDTH = $clog2(CHANNELS);

wire rdma_start;
wire [31:0] rdma_src_addr;
wire [31:0] rdma_transfer_bytes;
wire rdma_error;
wire [63:0] rdma_out_data;
wire rdma_out_valid;
wire rdma_out_ready;
wire rdma_out_last;

wire ibuffer_valid;
wire ibuffer_ready;
wire [63:0] ibuffer_data;
wire ibuffer_drain_done;

wire cfg_valid;
wire cfg_ready;
wire [CHANNEL_WIDTH-1:0] cfg_channel_id;
wire [2:0] cfg_feature_id;
wire signed [6:0] cfg_offset;
wire cfg_enable;
wire threshold_valid;
wire threshold_ready;
wire [31:0] threshold_value;

wire core_result_valid;
wire [511:0] core_result_data;
wire core_busy;
wire core_event_drop;
wire core_sfe_active;

wire obuffer_event_valid;
wire obuffer_event_start;
wire [63:0] obuffer_data;
wire obuffer_valid;
wire obuffer_ready;
wire obuffer_empty;
wire obuffer_overflow;

wire wdma_start;
wire [31:0] wdma_dst_addr;
wire wdma_busy;
wire wdma_done;
wire wdma_error;

wire system_done;
wire system_error;

assign M_AXI_AWID    = {ID_WIDTH{1'b0}};
assign M_AXI_ARID    = {ID_WIDTH{1'b0}};
assign M_AXI_AWLOCK  = 1'b0;
assign M_AXI_ARLOCK  = 1'b0;
assign M_AXI_AWCACHE = 4'b0011;
assign M_AXI_ARCACHE = 4'b0011;
assign M_AXI_AWPROT  = 3'b000;
assign M_AXI_ARPROT  = 3'b000;
assign M_AXI_AWQOS   = 4'b0000;
assign M_AXI_ARQOS   = 4'b0000;

assign IRQ = system_done || system_error;

controller #(
    .AW(6),
    .DW(32),
    .CHANNELS(CHANNELS)
) u_controller (
    .CLK(AXI_CLK),
    .RSTN(AXI_RSTN),
    .MAIN_CLK(MAIN_CLK),
    .MAIN_RSTN(MAIN_RSTN),
    .SFE_CLK(SFE_CLK),
    .SFE_RSTN(SFE_RSTN),

    .AWADDR(S_AXI_AWADDR[5:0]),
    .AWVALID(S_AXI_AWVALID),
    .AWREADY(S_AXI_AWREADY),
    .WDATA(S_AXI_WDATA),
    .WSTRB(S_AXI_WSTRB),
    .WVALID(S_AXI_WVALID),
    .WREADY(S_AXI_WREADY),
    .BRESP(S_AXI_BRESP),
    .BVALID(S_AXI_BVALID),
    .BREADY(S_AXI_BREADY),
    .ARADDR(S_AXI_ARADDR[5:0]),
    .ARVALID(S_AXI_ARVALID),
    .ARREADY(S_AXI_ARREADY),
    .RDATA(S_AXI_RDATA),
    .RRESP(S_AXI_RRESP),
    .RVALID(S_AXI_RVALID),
    .RREADY(S_AXI_RREADY),

    .rdma_start(rdma_start),
    .rdma_src_addr(rdma_src_addr),
    .rdma_transfer_bytes(rdma_transfer_bytes),
    .rdma_error(rdma_error),
    .input_drain_done(ibuffer_drain_done),

    .wdma_start(wdma_start),
    .wdma_dst_addr(wdma_dst_addr),
    .wdma_busy(wdma_busy),
    .wdma_done(wdma_done),
    .wdma_error(wdma_error),
    .obuffer_event_valid(obuffer_event_valid),
    .obuffer_event_start(obuffer_event_start),
    .obuffer_empty(obuffer_empty),
    .obuffer_overflow(obuffer_overflow),

    .core_busy(core_busy),
    .core_event_drop(core_event_drop),
    .threshold_valid(threshold_valid),
    .threshold_ready(threshold_ready),
    .threshold_value(threshold_value),

    .cfg_valid(cfg_valid),
    .cfg_ready(cfg_ready),
    .cfg_channel_id(cfg_channel_id),
    .cfg_feature_id(cfg_feature_id),
    .cfg_offset(cfg_offset),
    .cfg_enable(cfg_enable),

    .system_done(system_done),
    .system_error(system_error)
);

rdma u_rdma (
    .CLK(AXI_CLK),
    .RSTN(AXI_RSTN),
    .src_addr(rdma_src_addr),
    .transfer_bytes(rdma_transfer_bytes),
    .cfg_burst_beats(8'd16),
    .cfg_rd_out_limit(2'b00),
    .start(rdma_start),
    .busy(),
    .done(),
    .error(rdma_error),
    .read_beats(),
    .M_AXI_ARADDR(M_AXI_ARADDR),
    .M_AXI_ARLEN(M_AXI_ARLEN),
    .M_AXI_ARSIZE(M_AXI_ARSIZE),
    .M_AXI_ARBURST(M_AXI_ARBURST),
    .M_AXI_ARVALID(M_AXI_ARVALID),
    .M_AXI_ARREADY(M_AXI_ARREADY),
    .M_AXI_RDATA(M_AXI_RDATA),
    .M_AXI_RRESP(M_AXI_RRESP),
    .M_AXI_RLAST(M_AXI_RLAST),
    .M_AXI_RVALID(M_AXI_RVALID),
    .M_AXI_RREADY(M_AXI_RREADY),
    .out_data(rdma_out_data),
    .out_valid(rdma_out_valid),
    .out_ready(rdma_out_ready),
    .out_last(rdma_out_last)
);

IBuffer #(
    .DEPTH(IBUFFER_DEPTH)
) u_IBuffer (
    .s_clk(AXI_CLK),
    .s_rst_n(AXI_RSTN),
    .s_valid(rdma_out_valid),
    .s_ready(rdma_out_ready),
    .s_data(rdma_out_data),
    .s_last(rdma_out_last),
    .m_clk(SAMPLE_CLK),
    .m_rst_n(SAMPLE_RSTN),
    .m_valid(ibuffer_valid),
    .m_ready(ibuffer_ready),
    .m_data(ibuffer_data),
    .m_last(),
    .drain_done(ibuffer_drain_done)
);

NeuralCore #(
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
) u_NeuralCore (
    .s_clk(SAMPLE_CLK),
    .s_rst_n(SAMPLE_RSTN),
    .s_valid(ibuffer_valid),
    .s_ready(ibuffer_ready),
    .s_timestamp(ibuffer_data[63:32]),
    .s_channel_id(ibuffer_data[16 +: CHANNEL_WIDTH]),
    .s_sample(ibuffer_data[15:0]),
    .main_clk(MAIN_CLK),
    .main_rst_n(MAIN_RSTN),
    .threshold_valid(threshold_valid),
    .threshold_ready(threshold_ready),
    .threshold_value(threshold_value),
    .sfe_clk(SFE_CLK),
    .sfe_rst_n(SFE_RSTN),
    .cfg_valid(cfg_valid),
    .cfg_ready(cfg_ready),
    .cfg_channel_id(cfg_channel_id),
    .cfg_feature_id(cfg_feature_id),
    .cfg_offset(cfg_offset),
    .cfg_enable(cfg_enable),
    .result_valid(core_result_valid),
    .result_data(core_result_data),
    .busy(core_busy),
    .event_drop(core_event_drop),
    .pending_level(),
    .sfe_active(core_sfe_active)
);

OBuffer #(
    .DEPTH(OBUFFER_DEPTH)
) u_OBuffer (
    .s_clk(SFE_CLK),
    .s_rst_n(SFE_RSTN),
    .s_valid(core_result_valid),
    .s_data(core_result_data),
    .m_clk(AXI_CLK),
    .m_rst_n(AXI_RSTN),
    .event_valid(obuffer_event_valid),
    .event_start(obuffer_event_start),
    .m_data(obuffer_data),
    .m_valid(obuffer_valid),
    .m_ready(obuffer_ready),
    .empty(obuffer_empty),
    .overflow(obuffer_overflow)
);

wdma u_wdma (
    .CLK(AXI_CLK),
    .RSTN(AXI_RSTN),
    .dst_addr(wdma_dst_addr),
    .transfer_bytes(32'd64),
    .cfg_burst_beats(8'd8),
    .cfg_wr_out_limit(2'b00),
    .start(wdma_start),
    .busy(wdma_busy),
    .done(wdma_done),
    .error(wdma_error),
    .write_beats(),
    .in_data(obuffer_data),
    .in_valid(obuffer_valid),
    .in_ready(obuffer_ready),
    .M_AXI_AWADDR(M_AXI_AWADDR),
    .M_AXI_AWLEN(M_AXI_AWLEN),
    .M_AXI_AWSIZE(M_AXI_AWSIZE),
    .M_AXI_AWBURST(M_AXI_AWBURST),
    .M_AXI_AWVALID(M_AXI_AWVALID),
    .M_AXI_AWREADY(M_AXI_AWREADY),
    .M_AXI_WDATA(M_AXI_WDATA),
    .M_AXI_WSTRB(M_AXI_WSTRB),
    .M_AXI_WLAST(M_AXI_WLAST),
    .M_AXI_WVALID(M_AXI_WVALID),
    .M_AXI_WREADY(M_AXI_WREADY),
    .M_AXI_BRESP(M_AXI_BRESP),
    .M_AXI_BVALID(M_AXI_BVALID),
    .M_AXI_BREADY(M_AXI_BREADY)
);

endmodule
