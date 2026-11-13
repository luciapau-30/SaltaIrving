`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// tb_render: draws full 640x480 frames from vga_bitchange into PPM images.
// Scenarios come from sim/out/scenarios.txt (written by tools/make_frames.py):
//   name state level lives practice scroll runner_h timer crashes
//////////////////////////////////////////////////////////////////////////////////
module tb_render;
	reg        bright = 1;
	reg [9:0]  hCount = 0, vCount = 0;
	reg [3:0]  state = 0;
	reg [1:0]  level = 1;
	reg [3:0]  lives = 9;
	reg        practice = 0;
	reg [12:0] scroll = 0;
	reg [8:0]  runner_h = 0;
	reg [5:0]  timer = 0;
	reg [15:0] crash_bcd = 0;
	wire [11:0] rgb;

	vga_bitchange dut(.bright(bright), .hCount(hCount), .vCount(vCount),
	                  .state(state), .level(level), .lives(lives), .practice(practice),
	                  .scroll(scroll), .runner_h(runner_h), .timer(timer),
	                  .crash_bcd(crash_bcd), .rgb(rgb));

	integer fin, fo, r, x, y, st, lv, li, pr, sc, rh, tm, cr;
	reg [8*32-1:0] name;
	reg [8*96-1:0] path;

	initial begin
		fin = $fopen("sim/out/scenarios.txt", "r");
		while (!$feof(fin)) begin
			r = $fscanf(fin, "%s %d %d %d %d %d %d %d %d\n", name, st, lv, li, pr, sc, rh, tm, cr);
			if (r == 9) begin
				state = st; level = lv; lives = li; practice = pr; scroll = sc;
				runner_h = rh; timer = tm;
				crash_bcd[15:12] = cr / 1000 % 10; crash_bcd[11:8] = cr / 100 % 10;
				crash_bcd[7:4] = cr / 10 % 10;    crash_bcd[3:0] = cr % 10;
				$sformat(path, "sim/out/frame_%0s.ppm", name);
				fo = $fopen(path, "w");
				$fwrite(fo, "P3\n640 480\n15\n");
				for (y = 0; y < 480; y = y + 1) begin
					for (x = 0; x < 640; x = x + 1) begin
						vCount = y + 35; hCount = x + 145; #1;
						$fwrite(fo, "%0d %0d %0d\n", rgb[11:8], rgb[7:4], rgb[3:0]);
					end
				end
				$fclose(fo);
				$display("rendered %0s", name);
			end
		end
		$finish;
	end
endmodule
