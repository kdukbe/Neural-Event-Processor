`timescale 1ns / 1ps

// Keeps the SFE clock off while no complete event-window pair is waiting.
// This controller itself uses the ungated SFE clock, so it can always wake SFE.
module SFEClockControl #(
    parameter IDLE_HOLD_CYCLES = 4
)(
    input  wire base_clk,
    input  wire rst_n,

    // OFIFO write-side status. This remains alive while the SFE clock is off.
    input  wire work_pending_main,
    input  wire cfg_valid,

    // SFE status observed while its clock is running.
    input  wire sfe_busy,
    input  wire result_valid,

    output wire run_clk,
    output wire active
);

(* ASYNC_REG = "TRUE" *) reg work_sync1;
(* ASYNC_REG = "TRUE" *) reg work_sync2;

reg clock_enable;
reg [1:0] enable_pipe;
reg [$clog2(IDLE_HOLD_CYCLES+1)-1:0] idle_count;

wire wake_request;
wire sfe_idle;

assign wake_request = work_sync2 | cfg_valid;
assign sfe_idle     = !work_sync2 && !cfg_valid && !sfe_busy && !result_valid;
// BUFGCE synchronizes CE internally. Delay the public active flag so a
// ready/valid handshake cannot occur before the first gated clock edge.
assign active       = clock_enable && enable_pipe[1];

// Synchronize the Main-clock work status into the ungated SFE clock domain.
always @(posedge base_clk or negedge rst_n) begin
    if (!rst_n) begin
        work_sync1 <= 1'b0;
        work_sync2 <= 1'b0;
    end else begin
        work_sync1 <= work_pending_main;
        work_sync2 <= work_sync1;
    end
end

always @(posedge base_clk or negedge rst_n) begin
    if (!rst_n)
        enable_pipe <= 2'b11;
    else
        enable_pipe <= {enable_pipe[0], clock_enable};
end

// Keep the clock running for four idle base-clock cycles after the final result.
// Two cycles cover the work-status synchronizer; the remaining cycles let the
// result pulse reach the output buffer before the clock stops.
always @(posedge base_clk or negedge rst_n) begin
    if (!rst_n) begin
        clock_enable <= 1'b1;
        idle_count   <= 0;
    end else if (wake_request) begin
        clock_enable <= 1'b1;
        idle_count   <= 0;
    end else if (clock_enable && sfe_idle) begin
        if (idle_count == IDLE_HOLD_CYCLES-1) begin
            clock_enable <= 1'b0;
            idle_count   <= 0;
        end else begin
            idle_count <= idle_count + 1'b1;
        end
    end else begin
        idle_count <= 0;
    end
end

// Dedicated FPGA global-clock gate. CE_TYPE=SYNC prevents a shortened pulse.
BUFGCE #(
    .CE_TYPE("SYNC"),
    .IS_CE_INVERTED(1'b0),
    .IS_I_INVERTED(1'b0),
    .SIM_DEVICE("7SERIES")
) u_sfe_bufgce (
    .O(run_clk),
    .CE(clock_enable),
    .I(base_clk)
);

endmodule
