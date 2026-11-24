`timescale 1ns / 1ps

////////////////////////////////////////////////////////////////////////////////
// Module Name: game_sm
// Description: Geometry Dash FSM - Version 2 (group version 1 + jump counter,
//              potholes/rivers and 2 levels)
// Based on EE354 Number Lock FSM
//
//   0 INIT        lives <= 9, jumps <= 0, level <= 1, timer <= 0           -> MENU
//   1 MENU        SW1 & BtnL: level-1, SW1 & BtnR: level+1;  BtnC          -> LOAD
//   2 LOAD        scroll <= 0, vel <= 0, runner on the floor                -> PLAY
//   3 PLAY        timer <= 0; on tick: scroll + speed, update runner,
//                 jumps + 1 on every take-off
//                 hit -> CRASH (lives - 1 if !SW1);  finish & !hit -> LEVEL_CLEAR
//                 BtnD -> PAUSE
//   4 PAUSE       hold all;  BtnC -> PLAY
//   5 CRASH       on tick: timer + 1;  at timer = 59 (1 s):
//                 lives > 0 | SW1 -> LOAD,  lives = 0 & !SW1 -> GAME_OVER
//   6 LEVEL_CLEAR one clock: level < 2 -> level + 1, LOAD;  level = 2 -> WIN
//   7 GAME_OVER   hold all;  BtnC -> INIT
//   8 WIN         hold all;  BtnC -> INIT
//   SW0 (reset) forces INIT from any state. tick = one clock per frame (60 Hz).
////////////////////////////////////////////////////////////////////////////////

module game_sm(
    input clk,
    input reset,
    input tick,
    input btnC, btnD, btnL, btnR,
    input jump,
    input practice,

    output reg [3:0] state,
    output reg [1:0] level,
    output reg [3:0] lives,
    output reg [13:0] jumps,
    output reg [5:0] timer,
    output reg [12:0] scroll,
    output reg [8:0] runner_h
);

    // States 
    localparam INIT        = 4'd0,
               MENU        = 4'd1,
               LOAD        = 4'd2,
               PLAY        = 4'd3,
               PAUSE       = 4'd4,
               CRASH       = 4'd5,
               LEVEL_CLEAR = 4'd6,
               GAME_OVER   = 4'd7,
               WIN         = 4'd8;
               
    // SEC 1: GAME CONSTANTS AND VARIABLE NAMES         
    localparam [12:0] FINISH_SCROLL = 13'd7168;
    localparam [8:0] JUMP_HEIGHT = 9'd12;

    // params for tehe cube
    localparam [12:0] RUNNER_X = 13'd128;  // horizontal position of the cube , always stays here while world scrolls
    // world position = scroll + rx 

    // landing tolerance 
    localparam [8:0] LAND_TOLERANCE = 9'd12;

    // spike height
    localparam[8:0] SPIKE_HEIGHT = 9'd16;
    // obstacle types (level_rom): cone/spikes, barricade/crate, tall, block+spike, hole
    localparam[2:0] K_SPIKE = 3'd1, K_B32 = 3'd2, K_B64 = 3'd3, K_SPB = 3'd4, K_HOLE = 3'd5;

    // number of levels: 1 = Panama City, 2 = jungle
    localparam[1:0] LAST_LEVEL = 2'd2;



    // game speed based on level 

    wire [3:0] speed; 
    assign speed = (level == 2'd2) ? 4'd6 : 4'd5;   // px per frame: level 1 = 5, level 2 = 6
    // Temporary internal signals for testing





    // finsih condition 
    wire finish;
    assign finish = (scroll >= FINISH_SCROLL); 

    // vertical velocity 
    reg signed [5:0] vel; 

    initial begin
        state = INIT;
        level = 2'd1;
        lives = 4'd9;
        jumps = 14'd0;
        timer = 6'd0;
        scroll = 13'd0;
        runner_h = 9'd0;
        vel = 6'sd0; 
    end


    // runner's position in the world 

    wire[12:0] world_x = scroll + RUNNER_X; 

    // left and right boundaries of box , collision 
    wire[12:0] left_x = world_x + 12'd2; 
    wire[12:0] right_x = world_x + 12'd29; 

    // decide which tiles the urnner goes over

    wire[7:0] left_tile  = left_x / 13'd32;
    wire[7:0] right_tile = right_x / 13'd32; 



    // det obstacle types from level ROM 
    wire[2:0] left_obstacle_c, right_obstacle_c; 

    level_rom rom_left(.level(level), .tile(left_tile), .kind(left_obstacle_c));

    level_rom rom_right(.level(level), .tile(right_tile), .kind(right_obstacle_c)); 

    // keep obstacle types from rom 

    reg[2:0] left_obstacle , right_obstacle; 

    always @ (posedge clk) begin 

        if (reset || state == INIT || state == LOAD)  begin 

            left_obstacle <= 3'd0; 
            right_obstacle <= 3'd0; 


        end 


        else begin 
            left_obstacle <= left_obstacle_c; 
            right_obstacle <= right_obstacle_c; 
        end 
    end 

  

    // check if current tile has a block , both for tile a and b 

    wire left_block = (left_obstacle == K_B32) || (left_obstacle == K_B64) || (left_obstacle == K_SPB) ; 

    wire right_block = (right_obstacle == K_B32) || (right_obstacle == K_B64) || (right_obstacle == K_SPB) ; 

      // find the height of each block 
    wire[8:0] left_block_height = (left_obstacle == K_B64) ? 9'd64 : 9'd32; 
    wire[8:0] right_block_height = (right_obstacle == K_B64) ? 9'd64 : 9'd32; 


    // find whether runner is high enough to land on each block 
    wire [9:0] height_with_tolerance = runner_h + LAND_TOLERANCE; 


    // CHECK IF CUBE IS HIGH ENOUGH TO GO OVER 
    wire can_land_left = (height_with_tolerance >= left_block_height); // as long as its higher or touching it it's fine , can it go over? 
    wire can_land_right = (height_with_tolerance >= right_block_height);  // same here, just has to be above 


    // find surface height of each tile 

    wire [8:0] left_support = (left_block && can_land_left) ? left_block_height : 9'd0; 
    wire [8:0] right_support = (right_block && can_land_right) ? right_block_height : 9'd0; 

    // choose highest surface 
    wire[8:0] support_next = (left_support > right_support) ? left_support : right_support; 



    // crash detection code 

    // if block but also not higher to pass it -> hits the side of block 
    wire left_wall = left_block && !can_land_left; 
    wire right_wall = right_block && !can_land_right; 


    // crash if either tile has a wall collision 
    wire wallC = left_wall || right_wall; 


    // SPIKE COLLISION DETECTION: only conaider the middle of the spike 
    

    // runner's horizontal collision area , for spike specifically 
    // wx0 left edge in world coordinates 
    wire [12:0] sx0 = world_x + 13'd4;  // 4 pixels into cube's left edge 
    wire[12:0] sx1 = world_x + 13'd27;  // 27 pixels from cube's left edge 



    wire ovA_c = (sx0 <= (left_tile * 13'd32 + 13'd21)) &&
                 (sx1 >= (left_tile * 13'd32 + 13'd10));

    wire ovB_c = (sx0 <= (right_tile * 13'd32 + 13'd21)) &&
                 (sx1 >= (right_tile * 13'd32 + 13'd10)); 


    // HOLE COLLISION (pothole / river): only the runner's "feet" count
    // feet = cube x +8..+23, hole = tile x 4..27
    wire [12:0] fx0 = world_x + 13'd8;
    wire [12:0] fx1 = world_x + 13'd23;

    wire hoA_c = (fx0 <= (left_tile * 13'd32 + 13'd27)) &&
                 (fx1 >= (left_tile * 13'd32 + 13'd4));

    wire hoB_c = (fx0 <= (right_tile * 13'd32 + 13'd27)) &&
                 (fx1 >= (right_tile * 13'd32 + 13'd4));

    reg left_overlap, right_overlap; 
    reg left_hole_overlap, right_hole_overlap;
    always @ (posedge clk) begin 
        if (reset || state == INIT || state == LOAD) begin 
            left_overlap <= 1'b0; 
            right_overlap <= 1'b0; 
            left_hole_overlap <= 1'b0;
            right_hole_overlap <= 1'b0;
        end 
        else begin 
            left_overlap <= ovA_c; 
            right_overlap <= ovB_c ; 
            left_hole_overlap <= hoA_c;
            right_hole_overlap <= hoB_c;
        end 
    end 
    
    // Detect collisions with floor spikes or spikes on blocks
    wire spikeA =
        left_overlap &&
        (((left_obstacle == K_SPIKE) && (runner_h < SPIKE_HEIGHT)) ||
         ((left_obstacle == K_SPB) && (runner_h < 9'd48)));

    wire spikeB =
        right_overlap &&
        (((right_obstacle == K_SPIKE) && (runner_h < SPIKE_HEIGHT)) ||
         ((right_obstacle == K_SPB) && (runner_h < 9'd48)));

    wire spike_c = spikeA || spikeB;

    // fell in a pothole / river: standing on the floor (height 0) over a hole
    wire holeA = left_hole_overlap  && (left_obstacle  == K_HOLE);
    wire holeB = right_hole_overlap && (right_obstacle == K_HOLE);
    wire hole_c = (runner_h == 9'd0) && (holeA || holeB);



    // combine wall adn spike collisions 
    // runner crashes if hit wall and spike 
    // cimbinational 
    wire collision_next = wallC || spike_c || hole_c; 

    // reg collision adn support values 
    reg hit; 
    reg [8:0] support; 

    always @ (posedge clk) begin 
        if (reset || state == INIT || state == LOAD) begin 
            hit <= 1'b0; 
            support <= 9'd0; 

        end 

        else begin 

            hit <= collision_next; 
            support <= support_next; 
        end 





    end 



    /// where will runner be next frame 


    wire signed[10:0] height_signed = $signed({1'b0, runner_h});
    wire signed[10:0] velocity_signed = vel; 

    wire signed[10:0] next_height = height_signed + velocity_signed; 


    // check if runner has reached the support surface.
    // "<=" (not "==") so that a runner that is a few pixels BELOW a block top, but
    // within LAND_TOLERANCE, counts as standing on it and snaps up. The levels were
    // designed and proven beatable with this forgiving rule (tools/gd_model.py).
    wire grounded = (runner_h <= support);

    wire falling = (vel <= 6'sd0); 

    // only land when going down into a surface 
    wire landing = falling && (next_height <= $signed({1'b0, support}));



    // State machine
    always @(posedge clk) begin
        if (reset)
            state <= INIT;

        else begin
            case (state)

                INIT: begin
                    lives <= 4'd9; 
                    jumps <= 14'd0; 
                    level <= 2'd1; 
                    timer <= 6'd0; 
                    scroll <= 13'd0; 
                    runner_h <= 9'd0; 
                    state <= MENU; 
                    vel <= 6'sd0; 
                end

                MENU: begin
                    // PRACTICE MODE 

                    if (practice && btnL && level > 2'd1)
                        level <= level - 2'd1; // goto lower level 

                    else if (practice && btnR && level < LAST_LEVEL)
                        level <= level + 2'd1; // go to upper level 

                    if (btnC)
                        state <= LOAD;
                end

                LOAD: begin
                    
                    scroll <= 13'd0; 
                    runner_h <= 9'd0; 
                    state <= PLAY;
                    vel <= 6'sd0; 
                end

                PLAY: begin


                    timer <= 6'd0; 

                    if (btnD)
                        state <= PAUSE;


                    else if (tick) begin
                        if (hit) begin 
                            state <= CRASH;

                            // lose a life 
                            if (!practice && lives != 4'd0)
                                lives <= lives - 4'd1; 

                        end 

                        else if (finish)
                            state <= LEVEL_CLEAR;
                        

                        else begin 
                            // scroll world 
                            scroll <= scroll + speed; // for vga 

                            // cube hsould: 
                            // start on floor, jump when jump = 1, move upward, 
                            // slow down , fall, land , count each jump

                            // check if the runner is on the floor 
                            if (grounded) begin 

                                if (jump) begin 
                                    // start jump 
                                    runner_h <= support + JUMP_HEIGHT; 
                                    vel <= 6'sd11; 

                                    // count jumps
                                    if (jumps != 14'd9999)
                                        jumps <= jumps + 14'd1;

                                end 

                                else begin 
                                    // stay on floor
                                    vel <= 6'sd00; 
                                    runner_h <= support; 
                                end 

                            end 

                            // in the air 
                            else begin 
                                // check if runner is abt to land / will land
                                if (landing) begin 
                                    runner_h <= support; 
                                    vel <= 6'sd0; 
                                 end 

                                 else begin 

                                 // update runner height , cpontinue moving up or down 
                                 runner_h <= next_height[8:0]; 

                                 // apply gravity 
                                 if (vel > -6'sd12)
                                    vel <= vel -6'sd1; end 
                            end 
                        end 
                    end
                end



                PAUSE: begin
                    if (btnC)
                        state <= PLAY;
                end

                CRASH: begin // wait 60 frames, then if lives remain restart. if not goto gameover


                    if (tick) begin 

                        if (timer == 6'd59) begin 

                            // if lives remaining or we're practicing 
                            if (lives != 4'd0 || practice)
                                state <= LOAD; 

                                // else lost 
                            else 
                                state <= GAME_OVER;  end  

                    else begin 
                        timer <= timer + 6'd1; 

                    end 

                end 

        end 


                LEVEL_CLEAR: begin

                    if (level < LAST_LEVEL) begin 
                        level <= level +2'd1; 
                        state <= LOAD; 
                    end

                    else begin 
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

                default:
                    state <= INIT;

            endcase
        end
    end

endmodule
