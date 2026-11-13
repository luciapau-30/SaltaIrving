`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// tb_game_sm: self-checking testbench for game_sm
//
//  1. INIT -> MENU values, practice-only level select
//  2. Plays levels 1, 2 and 3 back-to-back using the jump schedules found by
//     tools/gd_model.py (sim/jumps_L*.mem), with a pause in the middle of level 1.
//     Every tick's (level, scroll, runner_h) is written to sim/out/trace_rtl.txt so
//     tools/check_trace.py can compare it bit-for-bit with the Python model.
//  3. WIN -> BtnC -> INIT -> MENU
//  4. No-jump run: crash, lives/crashes bookkeeping, 1-second CRASH screen,
//     nine crashes -> GAME_OVER
//  5. Practice mode crash keeps lives; SW0 reset from PLAY
//////////////////////////////////////////////////////////////////////////////////
module tb_game_sm;
	reg clk = 0;
	always #5 clk = ~clk;

	reg reset = 0, tick = 0, btnC = 0, btnD = 0, btnL = 0, btnR = 0, jump = 0, practice = 0;
	wire [3:0]  state;
	wire [1:0]  level;
	wire [3:0]  lives;
	wire [13:0] crashes;
	wire [5:0]  timer;
	wire [12:0] scroll;
	wire [8:0]  runner_h;

	game_sm dut(.clk(clk), .reset(reset), .tick(tick),
	            .btnC(btnC), .btnD(btnD), .btnL(btnL), .btnR(btnR),
	            .jump(jump), .practice(practice),
	            .state(state), .level(level), .lives(lives), .crashes(crashes),
	            .timer(timer), .scroll(scroll), .runner_h(runner_h));

	localparam INIT = 0, MENU = 1, LOAD = 2, PLAY = 3, PAUSE = 4, CRASH = 5,
	           LEVEL_CLEAR = 6, GAME_OVER = 7, WIN = 8;

	reg sched [0:4095];
	integer errors = 0, i, n, f, ticks, s0;

	task check(input cond, input [8*64-1:0] what);
		begin
			if (!cond) begin
				errors = errors + 1;
				$display("FAIL @%0t: %0s  (state=%0d level=%0d lives=%0d crashes=%0d scroll=%0d h=%0d)",
				         $time, what, state, level, lives, crashes, scroll, runner_h);
			end
		end
	endtask

	task do_tick;           // one frame
		begin
			@(negedge clk) tick = 1;
			@(negedge clk) tick = 0;
			repeat (3) @(negedge clk);
		end
	endtask

	task press_C; begin @(negedge clk) btnC = 1; @(negedge clk) btnC = 0; repeat (3) @(negedge clk); end endtask
	task press_D; begin @(negedge clk) btnD = 1; @(negedge clk) btnD = 0; repeat (3) @(negedge clk); end endtask
	task press_L; begin @(negedge clk) btnL = 1; @(negedge clk) btnL = 0; repeat (3) @(negedge clk); end endtask
	task press_R; begin @(negedge clk) btnR = 1; @(negedge clk) btnR = 0; repeat (3) @(negedge clk); end endtask

	// play the current level with the schedule in sched[]; returns after the clear
	task play_level(input integer lv, input integer nticks, input integer pause_at);
		integer k;
		begin
			for (k = 0; k < nticks; k = k + 1) begin
				check(state == PLAY && level == lv, "should be in PLAY on this level");
				if (k == pause_at) begin
					press_D;
					check(state == PAUSE, "BtnD -> PAUSE");
					s0 = scroll;
					repeat (10) do_tick;
					check(scroll == s0 && state == PAUSE, "PAUSE holds everything");
					press_C;
					check(state == PLAY, "BtnC -> back to PLAY");
				end
				jump = sched[k];
				do_tick;
				$fdisplay(f, "%0d %0d %0d", lv, scroll, runner_h);
			end
			jump = 0;
		end
	endtask

	initial begin
		$dumpfile("sim/out/tb_game_sm.vcd");
		$dumpvars(0, tb_game_sm);
		f = $fopen("sim/out/trace_rtl.txt", "w");

		// ---------------- 1. reset, INIT -> MENU
		reset = 1; repeat (3) @(negedge clk);
		check(state == INIT, "SW0 holds INIT");
		reset = 0; repeat (2) @(negedge clk);
		check(state == MENU, "INIT -> MENU");
		check(lives == 9 && level == 1 && crashes == 0 && timer == 0, "INIT values");

		press_R; check(level == 1, "BtnR ignored without SW1");
		practice = 1;
		press_R; check(level == 2, "SW1 & BtnR: level+1");
		press_R; check(level == 3, "SW1 & BtnR: level+1");
		press_R; check(level == 3, "level stays <= 3");
		press_L; check(level == 2, "SW1 & BtnL: level-1");
		press_L; press_L; check(level == 1, "level stays >= 1");
		practice = 0;

		// ---------------- 2. beat all three levels
		press_C;
		check(state == PLAY && scroll == 0 && runner_h == 0, "BtnC -> LOAD -> PLAY");
		$readmemb("sim/jumps_L1.mem", sched); play_level(1, 1793, 300);
		check(state == PLAY && level == 2 && scroll == 0, "L1 cleared -> LOAD L2 -> PLAY");
		$readmemb("sim/jumps_L2.mem", sched); play_level(2, 1435, -1);
		check(state == PLAY && level == 3 && scroll == 0, "L2 cleared -> LOAD L3 -> PLAY");
		$readmemb("sim/jumps_L3.mem", sched); play_level(3, 1196, -1);
		check(state == WIN, "L3 cleared -> WIN");
		check(crashes == 0 && lives == 9, "perfect run: no crashes");
		repeat (5) do_tick;
		check(state == WIN, "WIN holds");
		$fclose(f);

		// ---------------- 3. WIN -> INIT -> MENU
		press_C;
		check(state == MENU && level == 1 && lives == 9 && crashes == 0, "WIN + BtnC -> INIT -> MENU");

		// ---------------- 4. crash until GAME_OVER (no jumping)
		press_C;
		for (n = 1; n <= 9; n = n + 1) begin
			ticks = 0;
			while (state == PLAY && ticks < 5000) begin do_tick; ticks = ticks + 1; end
			check(state == CRASH, "runner that never jumps must crash");
			if (n == 1) $display("INFO no-jump crash on level 1 after %0d ticks (scroll %0d)", ticks, scroll);
			check(crashes == n && lives == 9 - n, "crash bookkeeping");
			ticks = 0;
			while (state == CRASH && ticks < 200) begin do_tick; ticks = ticks + 1; end
			check(ticks == 59, "CRASH screen lasts until timer = 59");
			if (n < 9) check(state == PLAY && scroll == 0, "CRASH -> LOAD -> PLAY while lives > 0");
			else       check(state == GAME_OVER, "last life -> GAME_OVER");
		end
		repeat (5) do_tick;
		check(state == GAME_OVER, "GAME_OVER holds");
		press_C;
		check(state == MENU && lives == 9 && crashes == 0, "GAME_OVER + BtnC -> INIT -> MENU");

		// ---------------- 5. practice mode + SW0 reset
		practice = 1;
		press_C;
		while (state == PLAY) do_tick;
		check(state == CRASH && lives == 9 && crashes == 1, "practice: crash keeps lives");
		while (state == CRASH) do_tick;
		check(state == PLAY, "practice: back to PLAY");
		repeat (20) do_tick;
		reset = 1; @(negedge clk); @(negedge clk);
		check(state == INIT, "SW0 -> INIT from PLAY");
		reset = 0; @(negedge clk); @(negedge clk);
		check(state == MENU && crashes == 0, "released SW0 -> MENU");

		if (errors == 0) $display("PASS tb_game_sm: all checks passed");
		else             $display("FAIL tb_game_sm: %0d check(s) failed", errors);
		$finish;
	end
endmodule
