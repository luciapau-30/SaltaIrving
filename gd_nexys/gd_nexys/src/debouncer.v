`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name:  debouncer
// Project:      FPGA Geometry Dash (EE354, Nexys A7-100T)
// Description:  Synchronises a push-button, waits until it has been stable for
//               2^N clocks (N = 20 -> ~10.5 ms at 100 MHz), then outputs
//                 level : the clean button level (used for "hold BtnU to jump")
//                 pulse : one clock high on each press  (used for BtnC/D/L/R)
//////////////////////////////////////////////////////////////////////////////////
module debouncer #(parameter N = 20) (
	input  clk,
	input  btn,
	output reg level,
	output pulse
	);

	reg [1:0]   sync;
	reg [N-1:0] cnt;
	reg         level_d;

	initial begin
		sync = 2'b00; cnt = {N{1'b0}}; level = 1'b0; level_d = 1'b0;
	end

	always @(posedge clk) begin
		sync    <= {sync[0], btn};
		level_d <= level;
		if (sync[1] == level)
			cnt <= {N{1'b0}};
		else begin
			cnt <= cnt + 1'b1;
			if (&cnt)
				level <= sync[1];
		end
	end

	assign pulse = level & ~level_d;

endmodule
