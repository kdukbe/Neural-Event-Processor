`timescale 1ns/1ps

// AXI-Lite registers and the minimum control needed to run one data file.
module controller #(
    parameter AW = 6,
    parameter DW = 32,
    parameter CHANNELS = 16
)(
    input  wire             CLK,
    input  wire             RSTN,
    input  wire             MAIN_CLK,
    input  wire             MAIN_RSTN,
    input  wire             SFE_CLK,
    input  wire             SFE_RSTN,

    // AXI4-Lite slave
    input  wire [AW-1:0]    AWADDR,
    input  wire             AWVALID,
    output wire             AWREADY,
    input  wire [DW-1:0]    WDATA,
    input  wire [DW/8-1:0]  WSTRB,
    input  wire             WVALID,
    output wire             WREADY,
    output wire [1:0]       BRESP,
    output wire             BVALID,
    input  wire             BREADY,
    input  wire [AW-1:0]    ARADDR,
    input  wire             ARVALID,
    output wire             ARREADY,
    output wire [DW-1:0]    RDATA,
    output wire [1:0]       RRESP,
    output wire             RVALID,
    input  wire             RREADY,

    // RDMA
    output reg              rdma_start,
    output wire [31:0]      rdma_src_addr,
    output wire [31:0]      rdma_transfer_bytes,
    input  wire             rdma_error,
    input  wire             input_drain_done,

    // WDMA and result buffer
    output reg              wdma_start,
    output wire [31:0]      wdma_dst_addr,
    input  wire             wdma_busy,
    input  wire             wdma_done,
    input  wire             wdma_error,
    input  wire             obuffer_event_valid,
    output reg              obuffer_event_start,
    input  wire             obuffer_empty,
    input  wire             obuffer_overflow,

    // NeuralCore
    input  wire             core_busy,
    input  wire             core_event_drop,

    // One common threshold; settings cross to MAIN_CLK.
    output wire             threshold_valid,
    input  wire             threshold_ready,
    output wire [31:0]      threshold_value,

    // Feature configuration in the SFE clock domain
    output wire             cfg_valid,
    input  wire             cfg_ready,
    output wire [$clog2(CHANNELS)-1:0] cfg_channel_id,
    output wire [2:0]       cfg_feature_id,
    output wire signed [6:0] cfg_offset,
    output wire             cfg_enable,

    output wire             system_done,
    output wire             system_error
);

localparam CHANNEL_WIDTH = $clog2(CHANNELS);
localparam CFG_WIDTH      = CHANNEL_WIDTH + 11;

localparam [AW-1:0] ADDR_CONTROL      = 6'h00;
localparam [AW-1:0] ADDR_STATUS       = 6'h04;
localparam [AW-1:0] ADDR_SRC_ADDR     = 6'h08;
localparam [AW-1:0] ADDR_INPUT_COUNT  = 6'h0c;
localparam [AW-1:0] ADDR_DST_ADDR     = 6'h10;
localparam [AW-1:0] ADDR_RESULT_COUNT = 6'h14;
localparam [AW-1:0] ADDR_FEATURE_CFG  = 6'h18;
localparam [AW-1:0] ADDR_THRESHOLD_VALUE   = 6'h1c;
localparam [AW-1:0] ADDR_THRESHOLD_STATUS  = 6'h20;

localparam WR_IDLE = 2'd0;
localparam WR_DATA = 2'd1;
localparam WR_RESP = 2'd2;

reg [1:0]    write_state;
reg [AW-1:0] write_addr;
reg          read_valid;
reg [31:0]   read_data;

wire aw_hs;
wire w_hs;
wire ar_hs;
wire feature_write;
wire threshold_write;
wire threshold_write_error;
reg write_error;
wire [31:0] write_mask;

reg [31:0] src_addr_reg;
reg [31:0] input_count_reg;
reg [31:0] dst_addr_reg;
wire threshold_fifo_ready;
wire threshold_pending;
wire [31:0] threshold_packet;

wire [CFG_WIDTH-1:0] cfg_s_data;
wire                 cfg_s_valid;
wire                 cfg_s_ready;
wire [CFG_WIDTH-1:0] cfg_m_data;
wire                 cfg_m_valid;

(* ASYNC_REG = "TRUE" *) reg core_busy_sync1;
(* ASYNC_REG = "TRUE" *) reg core_busy_sync2;
(* ASYNC_REG = "TRUE" *) reg core_drop_sync1;
(* ASYNC_REG = "TRUE" *) reg core_drop_sync2;

reg run;
reg done_reg;
reg error_reg;
reg input_drained;
reg write_active;
reg [31:0] result_count;

wire start_command;
wire start_invalid;
wire processing_done;

// AXI-Lite write channel
assign AWREADY = (write_state == WR_IDLE);
assign feature_write = (write_addr == ADDR_FEATURE_CFG);
assign threshold_write = (write_addr == ADDR_THRESHOLD_VALUE);
assign threshold_write_error = threshold_write && (run || (WSTRB != 4'hf) || (WDATA == 0));
assign WREADY  = (write_state == WR_DATA) &&
                 (!feature_write || (cfg_s_ready && !run)) &&
                 (!threshold_write || threshold_write_error || threshold_fifo_ready);
assign BVALID  = (write_state == WR_RESP);
assign BRESP   = write_error ? 2'b10 : 2'b00;
assign aw_hs   = AWVALID && AWREADY;
assign w_hs    = WVALID && WREADY;
assign write_mask = {{8{WSTRB[3]}}, {8{WSTRB[2]}},
                     {8{WSTRB[1]}}, {8{WSTRB[0]}}};

always @(posedge CLK or negedge RSTN) begin
    if (!RSTN) begin
        write_state <= WR_IDLE;
        write_addr  <= {AW{1'b0}};
        write_error <= 1'b0;
    end else begin
        case (write_state)
            WR_IDLE: begin
                if (aw_hs) begin
                    write_addr  <= AWADDR;
                    write_state <= WR_DATA;
                end
            end
            WR_DATA: begin
                if (w_hs) begin
                    write_error <= threshold_write_error;
                    write_state <= WR_RESP;
                end
            end
            WR_RESP: begin
                if (BREADY)
                    write_state <= WR_IDLE;
            end
            default: write_state <= WR_IDLE;
        endcase
    end
end

always @(posedge CLK or negedge RSTN) begin
    if (!RSTN) begin
        src_addr_reg    <= 32'd0;
        input_count_reg <= 32'd0;
        dst_addr_reg    <= 32'd0;
    end else if (w_hs) begin
        case (write_addr)
            ADDR_SRC_ADDR:
                src_addr_reg <= (WDATA & write_mask) |
                                (src_addr_reg & ~write_mask);
            ADDR_INPUT_COUNT:
                input_count_reg <= (WDATA & write_mask) |
                                   (input_count_reg & ~write_mask);
            ADDR_DST_ADDR:
                dst_addr_reg <= (WDATA & write_mask) |
                                (dst_addr_reg & ~write_mask);
            default: begin
            end
        endcase
    end
end

// AXI-Lite read channel
assign ARREADY = !read_valid;
assign RVALID  = read_valid;
assign RDATA   = read_data;
assign RRESP   = 2'b00;
assign ar_hs   = ARVALID && ARREADY;

always @(posedge CLK or negedge RSTN) begin
    if (!RSTN) begin
        read_valid <= 1'b0;
        read_data  <= 32'd0;
    end else begin
        if (ar_hs) begin
            read_valid <= 1'b1;
            case (ARADDR)
                ADDR_STATUS:
                    read_data <= {29'd0, error_reg, done_reg, run};
                ADDR_RESULT_COUNT:
                    read_data <= result_count;
                // bit 0 = every queued threshold reached SD; bit 1 = running.
                ADDR_THRESHOLD_STATUS:
                    read_data <= {30'd0, run, !threshold_pending};
                default:
                    read_data <= 32'd0;
            endcase
        end else if (read_valid && RREADY) begin
            read_valid <= 1'b0;
        end
    end
end

// Feature settings cross from AXI_CLK to SFE_CLK.
AFIFO #(.DW(32), .DEPTH(4)) u_threshold_fifo (
    .s_clk(CLK), .s_rst_n(RSTN),
    .s_valid(w_hs && threshold_write && !threshold_write_error),
    .s_ready(threshold_fifo_ready),
    .s_data(WDATA),
    .s_nonempty(threshold_pending),
    .m_clk(MAIN_CLK), .m_rst_n(MAIN_RSTN),
    .m_valid(threshold_valid), .m_ready(threshold_ready),
    .m_data(threshold_packet)
);
assign threshold_value = threshold_packet[31:0];

assign cfg_s_valid = w_hs && (write_addr == ADDR_FEATURE_CFG);
assign cfg_s_data = {
    WDATA[CHANNEL_WIDTH+10],
    WDATA[CHANNEL_WIDTH+3 +: 7],
    WDATA[CHANNEL_WIDTH +: 3],
    WDATA[0 +: CHANNEL_WIDTH]
};

wire unused_cfg_nonempty;

AFIFO #(
    .DW(CFG_WIDTH),
    .DEPTH(8)
) u_cfg_fifo (
    .s_clk(CLK),
    .s_rst_n(RSTN),
    .s_valid(cfg_s_valid),
    .s_ready(cfg_s_ready),
    .s_data(cfg_s_data),
    .s_nonempty(unused_cfg_nonempty),
    .m_clk(SFE_CLK),
    .m_rst_n(SFE_RSTN),
    .m_valid(cfg_m_valid),
    .m_ready(cfg_ready),
    .m_data(cfg_m_data)
);

assign cfg_valid      = cfg_m_valid;
assign cfg_channel_id = cfg_m_data[0 +: CHANNEL_WIDTH];
assign cfg_feature_id = cfg_m_data[CHANNEL_WIDTH +: 3];
assign cfg_offset     = cfg_m_data[CHANNEL_WIDTH+3 +: 7];
assign cfg_enable     = cfg_m_data[CHANNEL_WIDTH+10];

// Only Core status needs clock-domain synchronization here.
always @(posedge CLK or negedge RSTN) begin
    if (!RSTN) begin
        core_busy_sync1 <= 1'b0;
        core_busy_sync2 <= 1'b0;
        core_drop_sync1 <= 1'b0;
        core_drop_sync2 <= 1'b0;
    end else begin
        core_busy_sync1 <= core_busy;
        core_busy_sync2 <= core_busy_sync1;
        core_drop_sync1 <= core_event_drop;
        core_drop_sync2 <= core_drop_sync1;
    end
end

assign start_command = w_hs && (write_addr == ADDR_CONTROL) &&
                       WSTRB[0] && WDATA[0];
assign start_invalid = (src_addr_reg[2:0] != 3'b000) ||
                       (dst_addr_reg[5:0] != 6'b000000) ||
                       (input_count_reg == 32'd0) || threshold_pending;

assign rdma_src_addr       = src_addr_reg;
assign rdma_transfer_bytes = input_count_reg << 3;
assign wdma_dst_addr       = dst_addr_reg + (result_count << 6);

assign processing_done = input_drained &&
                         !core_busy_sync2 &&
                         obuffer_empty &&
                         !write_active &&
                         !wdma_busy;

assign system_done  = done_reg;
assign system_error = error_reg;

// One RDMA run, followed by one 64-byte WDMA run for each result.
always @(posedge CLK or negedge RSTN) begin
    if (!RSTN) begin
        run                 <= 1'b0;
        done_reg            <= 1'b0;
        error_reg           <= 1'b0;
        input_drained       <= 1'b0;
        write_active        <= 1'b0;
        result_count        <= 32'd0;
        rdma_start          <= 1'b0;
        wdma_start          <= 1'b0;
        obuffer_event_start <= 1'b0;
    end else begin
        rdma_start          <= 1'b0;
        wdma_start          <= 1'b0;
        obuffer_event_start <= 1'b0;

        if (start_command && !run) begin
            done_reg      <= 1'b0;
            error_reg     <= start_invalid;
            input_drained <= 1'b0;
            write_active  <= 1'b0;
            result_count  <= 32'd0;

            if (start_invalid) begin
                run      <= 1'b0;
                done_reg <= 1'b1;
            end else begin
                run        <= 1'b1;
                rdma_start <= 1'b1;
            end
        end else if (run) begin
            if (rdma_error || wdma_error ||
                core_drop_sync2 || obuffer_overflow)
                error_reg <= 1'b1;

            if (input_drain_done)
                input_drained <= 1'b1;

            if (obuffer_event_valid && !write_active && !wdma_busy) begin
                wdma_start          <= 1'b1;
                obuffer_event_start <= 1'b1;
                write_active        <= 1'b1;
            end

            if (wdma_done) begin
                write_active <= 1'b0;
                result_count <= result_count + 1'b1;
            end

            if (processing_done) begin
                run      <= 1'b0;
                done_reg <= 1'b1;
            end
        end
    end
end

endmodule
