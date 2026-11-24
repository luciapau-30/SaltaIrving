`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// SIMULATION-ONLY stand-in for the class-provided ee201_debouncer, with the same
// ports, so sim/run_all.sh can simulate vga_top with Icarus. Do NOT add this file
// to Vivado: the real design uses your ee201_debouncer.v.
//   DPB  = debounced button level      SCEN = one clock pulse per press
//   MCEN/CCEN are not used by vga_top (MCEN = SCEN, CCEN = DPB here)
// The button must be stable for 2^N_dc clocks before DPB changes.
//////////////////////////////////////////////////////////////////////////////////
module ee201_debouncer #(parameter N_dc = 25) (
	input CLK, RESET, PB,
	output reg DPB,
	output SCEN, MCEN, CCEN
	);
	reg [1:0] sync;
	reg [N_dc-1:0] cnt;
	reg dpb_d;
	initial begin sync = 2'b00; cnt = 0; DPB = 1'b0; dpb_d = 1'b0; end
	always @(posedge CLK, posedge RESET) begin
		if (RESET) begin
			sync <= 2'b00; cnt <= 0; DPB <= 1'b0; dpb_d <= 1'b0;
		end else begin
			sync  <= {sync[0], PB};
			dpb_d <= DPB;
			if (sync[1] == DPB) cnt <= 0;
			else begin
				cnt <= cnt + 1'b1;
				if (&cnt) DPB <= sync[1];
			end
		end
	end
	assign SCEN = DPB & ~dpb_d;
	assign MCEN = SCEN;
	assign CCEN = DPB;
endmodule
