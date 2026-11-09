`timescale 1ns / 1ps

module WindowController #(
    parameter CHANNELS = 16,
    parameter DEPTH    = 64
)(
    input clk,
    input rst_n,

    // PendingEventQueue
    input                              i_pending_valid,
    input                              i_pending_window_ready,
    output                             o_pending_pop,
    input [$clog2(CHANNELS)-1:0]       i_pending_channel_id,
    input [$clog2(DEPTH)-1:0]          i_pending_window_base,

    // WindowBuffer
    input                              i_read_ready,
    output                             o_read,
    output [$clog2(CHANNELS)-1:0]      o_read_channel_id,
    output [$clog2(DEPTH)-1:0]         o_read_base,
    output [$clog2(DEPTH)-1:0]         o_read_index,

    input                              i_window_valid,
    input                              i_window_last,

    // WindowFIFO
    input                              i_window_ready,

    // OFIFO
    output                             o_event_valid,
    input                              i_event_ready,

    // MainPath
    output                             o_busy
);

localparam IDLE      = 2'd0;
localparam COPY      = 2'd1;
localparam WAIT_LAST = 2'd2;
localparam SEND      = 2'd3;

reg [1:0] state;
reg [$clog2(DEPTH)-1:0] read_index;

assign o_pending_pop = (state == SEND) && i_event_ready;

assign o_read            = (state == COPY) && i_read_ready;
assign o_read_channel_id = i_pending_channel_id;
assign o_read_base       = i_pending_window_base;
assign o_read_index      = read_index;

assign o_event_valid = (state == SEND);

assign o_busy = (state != IDLE);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state      <= IDLE;
        read_index <= 0;
    end else begin
        case (state)
            IDLE: begin
                if (i_pending_valid && i_pending_window_ready) begin
                    read_index <= 0;
                    state      <= COPY;
                end
            end

            COPY: begin
                if (o_read) begin
                    if (read_index == DEPTH-1)
                        state <= WAIT_LAST;
                    else
                        read_index <= read_index + 1'b1;
                end
            end

            WAIT_LAST: begin
                if (i_window_valid && i_window_last && i_window_ready)
                    state <= SEND;
            end

            SEND: begin
                if (i_event_ready)
                    state <= IDLE;
            end

            default: state <= IDLE;
        endcase
    end
end

endmodule
