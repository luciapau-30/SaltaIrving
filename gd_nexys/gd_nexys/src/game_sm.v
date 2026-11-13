`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name:  game_sm
// Project:      FPGA Geometry Dash (EE354, Nexys A7-100T)
// Description:  Main state machine + runner physics.
//
//   States (numbers match the design diagram and what SW15 shows on the SSDs):
//     0 INIT        lives <= 9, crashes <= 0, level <= 1, timer <= 0      -> MENU
//     1 MENU        SW1 & BtnL: level-1, SW1 & BtnR: level+1;  BtnC        -> LOAD
//     2 LOAD        scroll <= 0, vel <= 0, runner on the floor              -> PLAY
//     3 PLAY        timer <= 0; on tick: scroll + speed, update runner
//                   hit -> CRASH (crashes+1, lives-1 if !SW1)
//                   finish & !hit -> LEVEL_CLEAR;  BtnD -> PAUSE
//     4 PAUSE       hold all;  BtnC -> PLAY
//     5 CRASH       on tick: timer + 1
//                   timer = 59 & (lives > 0 | SW1)  -> LOAD
//                   timer = 59 & lives = 0 & !SW1   -> GAME_OVER
//     6 LEVEL_CLEAR one clock: level < 3 -> level+1, LOAD;  level = 3 -> WIN
//     7 GAME_OVER   hold all;  BtnC -> INIT
//     8 WIN         hold all;  BtnC -> INIT
//   SW0 (reset) forces INIT from any state.
//
//   tick = one clock per video frame (60 Hz). PLAY and CRASH act on tick.
//
//   World/physics (bit-exact with tools/gd_model.py):
//     - The world is a row of 32-px tiles (level_rom). scroll = world x at screen x 0.
//     - The runner is 32x32 at screen x 128. runner_h = height of its bottom above
//       the floor. vel = vertical speed (px/frame, + is up).
//     - Between ticks the 'sense' logic looks at the 1-2 tiles under the runner and
//       works out the highest block top it can stand on (support) and whether it
//       has touched a spike or the side of a block (hit). It is pipelined over two
//       registered stages so every 100 MHz path stays short; positions only change
//       once per frame, so the values are always settled by the next tick.
//////////////////////////////////////////////////////////////////////////////////
module game_sm(
	input clk,
	input reset,              // SW0 (synchronised): go to INIT
	input tick,               // 1 clock per frame
	input btnC, btnD, btnL, btnR,   // 1-clock pulses (debounced)
	input jump,               // BtnU held (debounced level)
	input practice,           // SW1: unlimited lives + level select
	output reg [3:0]  state,
	output reg [1:0]  level,      // 1..3
	output reg [3:0]  lives,      // 0..9
	output reg [13:0] crashes,    // 0..9999
	output reg [5:0]  timer,      // 0..59 (CRASH screen timer)
	output reg [12:0] scroll,     // world x of the left screen edge
	output reg [8:0]  runner_h    // runner bottom height above floor (px)
	);

	// ---------------- states ----------------
	localparam INIT        = 4'd0,
	           MENU        = 4'd1,
	           LOAD        = 4'd2,
	           PLAY        = 4'd3,
	           PAUSE       = 4'd4,
	           CRASH       = 4'd5,
	           LEVEL_CLEAR = 4'd6,
	           GAME_OVER   = 4'd7,
	           WIN         = 4'd8;

	// ---------------- tuning (keep in sync with tools/gd_model.py) ----------------
	localparam [12:0] RX            = 13'd128;   // runner screen x
	localparam [12:0] FINISH_SCROLL = 13'd7168;  // level done when scroll reaches this
	localparam [8:0]  JUMP_V        = 9'd12;     // take-off speed
	localparam [8:0]  SNAP          = 9'd12;     // landing tolerance
	localparam [8:0]  SPIKE_H       = 9'd16;     // clearance needed over a spike

	// tile kinds (level_rom)
	localparam [2:0] K_SPIKE = 3'd1, K_B32 = 3'd2, K_B64 = 3'd3, K_SPB = 3'd4;

	reg signed [5:0] vel;     // -12..+11

	initial begin
		state = INIT; level = 2'd1; lives = 4'd9; crashes = 14'd0; timer = 6'd0;
		scroll = 13'd0; runner_h = 9'd0; vel = 6'sd0;
	end

	// =====================================================================
	// Sense logic: what is under / around the runner right now
	// =====================================================================
	wire [12:0] wx0 = scroll + RX;          // runner left edge in world x
	wire [12:0] wa  = wx0 + 13'd2;          // body hit-box (28 px wide)
	wire [12:0] wb  = wx0 + 13'd29;
	wire [7:0]  tA  = wa[12:5];             // the (up to) two tiles it overlaps
	wire [7:0]  tB  = wb[12:5];
	wire [2:0]  kA_c, kB_c;

	level_rom romA(.level(level), .tile(tA), .kind(kA_c));
	level_rom romB(.level(level), .tile(tB), .kind(kB_c));

	// spike hit-box: tile x 10..21 vs runner x +4..+27
	wire [12:0] sx0 = wx0 + 13'd4;
	wire [12:0] sx1 = wx0 + 13'd27;
	wire ovA_c = (sx0 <= {tA, 5'd21}) && (sx1 >= {tA, 5'd10});
	wire ovB_c = (sx0 <= {tB, 5'd21}) && (sx1 >= {tB, 5'd10});

	// Stage 1 registers: tile kinds + spike overlap. scroll/runner_h only change on a
	// tick (once per frame), so this extra pipeline stage costs nothing but keeps the
	// 100 MHz paths short. Cleared in INIT/LOAD (the start of every level is empty).
	reg [2:0] kA, kB;
	reg       ovA, ovB;
	initial begin kA = 3'd0; kB = 3'd0; ovA = 1'b0; ovB = 1'b0; end
	always @(posedge clk) begin
		if (state == LOAD || state == INIT) begin
			kA <= 3'd0; kB <= 3'd0; ovA <= 1'b0; ovB <= 1'b0;
		end else begin
			kA <= kA_c; kB <= kB_c; ovA <= ovA_c; ovB <= ovB_c;
		end
	end

	// Stage 2: what the runner can stand on, and whether it hit something
	wire blkA = (kA == K_B32) || (kA == K_B64) || (kA == K_SPB);
	wire blkB = (kB == K_B32) || (kB == K_B64) || (kB == K_SPB);
	wire [8:0] topA = (kA == K_B64) ? 9'd64 : 9'd32;
	wire [8:0] topB = (kB == K_B64) ? 9'd64 : 9'd32;
	wire [9:0] h_snap = {1'b0, runner_h} + {1'b0, SNAP};
	wire canA = h_snap >= {1'b0, topA};     // high enough to land on it
	wire canB = h_snap >= {1'b0, topB};

	wire [8:0] supA = (blkA && canA) ? topA : 9'd0;
	wire [8:0] supB = (blkB && canB) ? topB : 9'd0;
	wire [8:0] support_c = (supA > supB) ? supA : supB;

	wire wall_c  = (blkA && !canA) || (blkB && !canB);
	wire spike_c = (ovA && (((kA == K_SPIKE) && (runner_h < SPIKE_H)) ||
	                        ((kA == K_SPB)   && (runner_h < 9'd32 + SPIKE_H)))) ||
	               (ovB && (((kB == K_SPIKE) && (runner_h < SPIKE_H)) ||
	                        ((kB == K_SPB)   && (runner_h < 9'd32 + SPIKE_H))));
	wire hit_c = wall_c || spike_c;

	reg       hit;
	reg [8:0] support;
	initial begin hit = 1'b0; support = 9'd0; end

	always @(posedge clk) begin
		if (state == LOAD || state == INIT) begin   // scroll/runner are being reset
			hit     <= 1'b0;
			support <= 9'd0;
		end else begin
			hit     <= hit_c;
			support <= support_c;
		end
	end

	// =====================================================================
	// Runner physics (used on a PLAY tick)
	// =====================================================================
	wire               finish   = (scroll >= FINISH_SCROLL);
	wire [3:0]         speed    = (level == 2'd3) ? 4'd6 : (level == 2'd2) ? 4'd5 : 4'd4;
	wire               grounded = (runner_h <= support);
	wire signed [10:0] h_air    = $signed({2'b00, runner_h}) + $signed({{5{vel[5]}}, vel});  // h + v
	wire               lands    = (h_air <= $signed({2'b00, support}));
	wire signed [5:0]  vel_fall = (vel <= -6'sd12) ? -6'sd12 : vel - 6'sd1;

	// =====================================================================
	// State machine
	// =====================================================================
	always @(posedge clk) begin
		if (reset) begin
			state <= INIT;
		end else begin
			case (state)
			INIT: begin
				lives    <= 4'd9;
				crashes  <= 14'd0;
				level    <= 2'd1;
				timer    <= 6'd0;
				scroll   <= 13'd0;      // (also park the runner so MENU shows the start)
				runner_h <= 9'd0;
				vel      <= 6'sd0;
				state    <= MENU;
			end

			MENU: begin
				if (practice && btnL && level > 2'd1)
					level <= level - 2'd1;
				else if (practice && btnR && level < 2'd3)
					level <= level + 2'd1;
				if (btnC)
					state <= LOAD;
			end

			LOAD: begin
				scroll   <= 13'd0;
				vel      <= 6'sd0;
				runner_h <= 9'd0;       // y <= floor
				state    <= PLAY;
			end

			PLAY: begin
				timer <= 6'd0;
				if (btnD) begin
					state <= PAUSE;
				end else if (tick) begin
					if (hit) begin
						state <= CRASH;
						if (crashes != 14'd9999)
							crashes <= crashes + 14'd1;
						if (!practice && lives != 4'd0)
							lives <= lives - 4'd1;
					end else if (finish) begin
						state <= LEVEL_CLEAR;
					end else begin
						scroll <= scroll + {9'd0, speed};
						if (grounded) begin
							if (jump) begin
								runner_h <= support + JUMP_V;
								vel      <= 6'sd11;           // JUMP_V - gravity
							end else begin
								runner_h <= support;
								vel      <= 6'sd0;
							end
						end else if (lands) begin
							runner_h <= support;
							vel      <= 6'sd0;
						end else begin
							runner_h <= h_air[8:0];
							vel      <= vel_fall;
						end
					end
				end
			end

			PAUSE: begin
				if (btnC)
					state <= PLAY;
			end

			CRASH: begin
				if (timer == 6'd59)
					state <= (lives != 4'd0 || practice) ? LOAD : GAME_OVER;
				else if (tick)
					timer <= timer + 6'd1;
			end

			LEVEL_CLEAR: begin
				if (level < 2'd3) begin
					level <= level + 2'd1;
					state <= LOAD;
				end else begin
					state <= WIN;
				end
			end

			GAME_OVER: begin
				if (btnC)
					state <= INIT;
			end

			WIN: begin
				if (btnC)
					state <= INIT;
			end

			default: state <= INIT;
			endcase
		end
	end

endmodule
