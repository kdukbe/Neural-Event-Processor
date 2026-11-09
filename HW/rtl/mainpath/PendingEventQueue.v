`timescale 1ns / 1ps

module PendingEventQueue #(
    parameter CHANNELS     = 16,
    parameter WINDOW_DEPTH = 64,
    parameter DEPTH        = 8,
    parameter POST_SAMPLES = 30 // wating sample
)(
    input clk,
    input rst_n,

    // IFIFO
    input                              i_sample_valid,
    input [$clog2(CHANNELS)-1:0]       i_sample_channel_id,

    // WindowBuffer
    input [$clog2(WINDOW_DEPTH)-1:0]   i_event_next_addr,

    // SD
    input                              i_event_valid,
    input [31:0]                       i_event_id,
    input [31:0]                       i_event_timestamp,
    input [$clog2(CHANNELS)-1:0]       i_event_channel_id,
    input signed [15:0]                i_event_sample,

    // WindowController
    output                             o_valid,
    input                              i_pop,
    output reg [$clog2(CHANNELS)-1:0]  o_channel_id,
    output reg [$clog2(WINDOW_DEPTH)-1:0] o_window_base,
    output reg                         o_window_ready,

    // OFIFO 
    output reg [31:0]                  o_id,
    output reg [31:0]                  o_timestamp,
    output reg signed [15:0]           o_sample,

    // MainPath
    output reg                         o_overflow,
    output [$clog2(DEPTH):0]           o_level
);

localparam PTR_WIDTH         = $clog2(DEPTH);
localparam WINDOW_ADDR_WIDTH = $clog2(WINDOW_DEPTH);
localparam INITIAL_SAMPLES   = WINDOW_DEPTH - POST_SAMPLES;
// 8 bits are enough if an event waits for fewer than 256 channel samples.
localparam SAMPLE_COUNT_WIDTH = 8;

reg [31:0]                  id_mem [0:DEPTH-1];
reg [31:0]                  timestamp_mem [0:DEPTH-1];
reg [$clog2(CHANNELS)-1:0]  channel_mem [0:DEPTH-1];
reg signed [15:0]           sample_mem [0:DEPTH-1];
reg [WINDOW_ADDR_WIDTH-1:0] base_mem [0:DEPTH-1];
reg [SAMPLE_COUNT_WIDTH-1:0] event_sample_count_mem [0:DEPTH-1];

reg [SAMPLE_COUNT_WIDTH-1:0] channel_sample_count [0:CHANNELS-1];

reg [PTR_WIDTH-1:0] write_ptr;
reg [PTR_WIDTH-1:0] read_ptr;
reg [PTR_WIDTH:0]   count;

wire push;
wire pop;
wire can_push;

reg [WINDOW_ADDR_WIDTH:0] window_start_sum;
reg [WINDOW_ADDR_WIDTH-1:0] event_window_base;
reg [SAMPLE_COUNT_WIDTH-1:0] samples_after_event;

integer ch;

assign o_valid = (count != 0);
assign pop = o_valid && i_pop;
assign can_push = (count < DEPTH) || pop;
assign push = i_event_valid && can_push;
assign o_level = count;

// calculate base adress
always @(*) begin
    window_start_sum = {1'b0, i_event_next_addr} + WINDOW_DEPTH - INITIAL_SAMPLES;

    if (window_start_sum >= WINDOW_DEPTH)
        event_window_base = window_start_sum - WINDOW_DEPTH;
    else
        event_window_base = window_start_sum[WINDOW_ADDR_WIDTH-1:0];
end

// Send window_ready
always @(*) begin
    o_id           = 0;
    o_timestamp    = 0;
    o_channel_id   = 0;
    o_sample       = 16'd0;
    o_window_base  = 0;
    o_window_ready = 1'b0;
    samples_after_event = 0;

    if (o_valid) begin
        o_id          = id_mem[read_ptr];
        o_timestamp   = timestamp_mem[read_ptr];
        o_channel_id  = channel_mem[read_ptr];
        o_sample      = sample_mem[read_ptr];
        o_window_base = base_mem[read_ptr];

        samples_after_event = channel_sample_count[channel_mem[read_ptr]] - event_sample_count_mem[read_ptr];

        if (samples_after_event >= POST_SAMPLES)
            o_window_ready = 1'b1;
    end
end

// Count received samples
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for (ch = 0; ch < CHANNELS; ch = ch + 1)
            channel_sample_count[ch] <= 0;
    end else if (i_sample_valid) begin
        channel_sample_count[i_sample_channel_id] <= channel_sample_count[i_sample_channel_id] + 1'b1;
    end
end

// FIFO
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        write_ptr  <= 0;
        read_ptr   <= 0;
        count      <= 0;
        o_overflow <= 1'b0;
    end else begin
        o_overflow <= i_event_valid && !can_push;

        if (push) begin
            if (write_ptr == DEPTH-1)
                write_ptr <= 0;
            else
                write_ptr <= write_ptr + 1'b1;
        end

        if (pop) begin
            if (read_ptr == DEPTH-1)
                read_ptr <= 0;
            else
                read_ptr <= read_ptr + 1'b1;
        end

        case ({push, pop})
            2'b10: count <= count + 1'b1;
            2'b01: count <= count - 1'b1;
            default: count <= count;
        endcase
    end
end

// Store event
always @(posedge clk) begin
    if (push) begin
        id_mem[write_ptr]                 <= i_event_id;
        timestamp_mem[write_ptr]          <= i_event_timestamp;
        channel_mem[write_ptr]            <= i_event_channel_id;
        sample_mem[write_ptr]             <= i_event_sample;
        base_mem[write_ptr]               <= event_window_base;
        event_sample_count_mem[write_ptr] <= channel_sample_count[i_event_channel_id];
    end
end

endmodule
