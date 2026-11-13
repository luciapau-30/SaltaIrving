`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// tb_top: whole-chip test of vga_top at 100 MHz
//   - checks hSync / vSync periods (800 x 525 pixels at 25 MHz)
//   - checks exactly one game tick per frame
//   - presses BtnC through the real debouncer: MENU -> LOAD -> PLAY
//   - holds BtnU and checks the runner leaves the ground
//   - decodes the seven-segment scan: "L1 9 0000", then SW15 -> "StAtE  3"
//   - captures one frame from the VGA pins to sim/out/vga_capture.ppm
// The debouncer is shortened (DEBOUNCE_BITS = 4) so presses take 16 clocks.
//////////////////////////////////////////////////////////////////////////////////
module tb_top;
	reg ClkPort = 0;
	always #5 ClkPort = ~ClkPort;

	reg BtnC = 0, BtnU = 0, BtnD = 0, BtnL = 0, BtnR = 0, Sw0 = 0, Sw1 = 0, Sw15 = 0;
	wire hSync, vSync, Dp, QuadSpiFlashCS;
	wire [3:0] vgaR, vgaG, vgaB;
	wire An0, An1, An2, An3, An4, An5, An6, An7, Ca, Cb, Cc, Cd, Ce, Cf, Cg;

	vga_top #(.DEBOUNCE_BITS(4)) dut(
		.ClkPort(ClkPort), .BtnC(BtnC), .BtnU(BtnU), .BtnD(BtnD), .BtnL(BtnL), .BtnR(BtnR),
		.Sw0(Sw0), .Sw1(Sw1), .Sw15(Sw15),
		.hSync(hSync), .vSync(vSync), .vgaR(vgaR), .vgaG(vgaG), .vgaB(vgaB),
		.An0(An0), .An1(An1), .An2(An2), .An3(An3), .An4(An4), .An5(An5), .An6(An6), .An7(An7),
		.Ca(Ca), .Cb(Cb), .Cc(Cc), .Cd(Cd), .Ce(Ce), .Cf(Cf), .Cg(Cg), .Dp(Dp),
		.QuadSpiFlashCS(QuadSpiFlashCS));

	// The example display_controller has no reset for hCount/vCount. On the FPGA they
	// power up as 0; in simulation they start as X, so give them the same start value.
	initial begin dut.dc.hCount = 0; dut.dc.vCount = 0; end

	integer errors = 0;
	task check(input cond, input [8*64-1:0] what);
		begin
			if (!cond) begin
				errors = errors + 1;
				$display("FAIL @%0t ns: %0s", $time, what);
			end else
				$display("ok   %0s", what);
		end
	endtask

	// ---------------- sync periods and ticks
	integer hs_last = 0, hs_period = 0, vs_last = 0, vs_period = 0, cyc = 0;
	integer ticks = 0, frames = 0;
	reg hs_d = 0, vs_d = 0;
	always @(posedge ClkPort) begin
		cyc = cyc + 1;
		hs_d <= hSync; vs_d <= vSync;
		if (hSync && !hs_d) begin hs_period = cyc - hs_last; hs_last = cyc; end
		if (vSync && !vs_d) begin vs_period = cyc - vs_last; vs_last = cyc; frames = frames + 1; end
		if (dut.tick) ticks = ticks + 1;
	end

	// ---------------- VGA capture of frame number cap_frame (sampled mid-pixel)
	integer cap_frame = 4, fo, px = 0;
	initial begin
		fo = $fopen("sim/out/vga_capture.ppm", "w");
		$fwrite(fo, "P3\n640 480\n15\n");
	end
	always @(negedge dut.dc.clk25) begin
		if (frames == cap_frame && dut.dc.vCount >= 35 && dut.dc.vCount < 515 &&
		    dut.dc.hCount >= 145 && dut.dc.hCount < 785) begin
			// bright is registered one pixel late, so pixel x is on screen while hCount = x+145
			$fwrite(fo, "%0d %0d %0d\n", vgaR, vgaG, vgaB);
			px = px + 1;
		end
	end

	// ---------------- seven-segment decode
	function [7:0] seg2char(input [6:0] s);
		case (s)
			7'b0000001: seg2char = "0"; 7'b1001111: seg2char = "1"; 7'b0010010: seg2char = "2";
			7'b0000110: seg2char = "3"; 7'b1001100: seg2char = "4"; 7'b0100100: seg2char = "5";
			7'b0100000: seg2char = "6"; 7'b0001111: seg2char = "7"; 7'b0000000: seg2char = "8";
			7'b0000100: seg2char = "9"; 7'b0001000: seg2char = "A"; 7'b0110000: seg2char = "E";
			7'b1110001: seg2char = "L"; 7'b0011000: seg2char = "P"; 7'b1110000: seg2char = "t";
			7'b1111111: seg2char = " "; default: seg2char = "?";
		endcase
	endfunction
	reg [8*8-1:0] ssd_text;
	task read_ssd;           // one full scan of the 8 digits
		integer k, d;
		reg [7:0] an;
		begin
			ssd_text = "????????";
			for (k = 0; k < 8; k = k + 1) begin
				repeat (131072) @(posedge ClkPort);
				@(negedge ClkPort);
				an = {An7, An6, An5, An4, An3, An2, An1, An0};
				for (d = 0; d < 8; d = d + 1)
					if (an == ~(8'b1 << d))
						ssd_text[8*d +: 8] = seg2char({Ca, Cb, Cc, Cd, Ce, Cf, Cg});
			end
		end
	endtask

	initial begin
		repeat (100) @(posedge ClkPort);
		check(dut.sm.state == 1, "power-up INIT -> MENU");

		// press BtnC for 50 clocks (debounce needs 16 stable clocks)
		BtnC = 1; repeat (50) @(posedge ClkPort); BtnC = 0;
		repeat (50) @(posedge ClkPort);
		check(dut.sm.state == 3, "BtnC (debounced) -> LOAD -> PLAY");

		wait (frames == 2);
		BtnU = 1;                                  // hold jump
		wait (frames == 4);
		repeat (100) @(posedge ClkPort);           // let this frame's tick happen
		check(dut.sm.runner_h > 0, "holding BtnU makes the runner jump");
		check(hs_period == 3200, "hSync period = 800 px x 4 clocks");
		check(vs_period == 1680000, "vSync period = 525 lines (59.5 Hz)");
		check(ticks == frames, "one game tick per frame");
		check(dut.sm.scroll == 4 * (ticks - 1) || dut.sm.scroll == 4 * ticks, "scroll advances 4 px per tick on level 1");

		read_ssd;
		$display("SSD shows \"%0s\"", ssd_text);
		check(ssd_text == "L1 90000", "SSD = L1 9 0000");
		Sw15 = 1;
		read_ssd;
		$display("SSD shows \"%0s\"", ssd_text);
		check(ssd_text == "5tAtE  3", "SW15: SSD = StAtE  3 (S and 5 share segments)");

		wait (frames == cap_frame + 1);
		$fclose(fo);
		check(px == 640 * 480, "captured a full 640x480 frame from the VGA pins");
		check(QuadSpiFlashCS == 1 && Dp == 1, "flash CS and DP held high");

		if (errors == 0) $display("PASS tb_top: all checks passed");
		else             $display("FAIL tb_top: %0d check(s) failed", errors);
		$finish;
	end

	initial begin #200_000_000; $display("FAIL tb_top: timeout"); $finish; end
endmodule
