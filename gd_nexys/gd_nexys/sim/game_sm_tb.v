`timescale 1ns / 1ps

module game_sm_tb;

    // Inputs to game_sm
    reg clk;
    reg reset;
    reg tick;
    reg btnC, btnD, btnL, btnR;
    reg jump;
    reg practice;

    // Outputs from game_sm
    wire [3:0] state;
    wire [1:0] level;
    wire [3:0] lives;
    wire [13:0] jumps;
    wire [5:0] timer;
    wire [12:0] scroll;
    wire [8:0] runner_h;

    // State values
    localparam MENU  = 4'd1;
    localparam PLAY  = 4'd3;
    localparam CRASH = 4'd5;

    integer i;
    integer errors;

    // Instantiate the game FSM
    game_sm uut (
        .clk(clk),
        .reset(reset),
        .tick(tick),
        .btnC(btnC),
        .btnD(btnD),
        .btnL(btnL),
        .btnR(btnR),
        .jump(jump),
        .practice(practice),
        .state(state),
        .level(level),
        .lives(lives),
        .jumps(jumps),
        .timer(timer),
        .scroll(scroll),
        .runner_h(runner_h)
    );

    // 100 MHz clock: 10 ns period
    initial clk = 0;

    always #5 clk = ~clk;

    // Generate one frame tick
    task frame_tick;
    begin
        @(negedge clk);
        tick = 1;

        @(negedge clk);
        tick = 0;

        // Let registered signals update
        repeat (3) @(negedge clk);
    end
    endtask

    // Simulate pressing the center button
    task press_center;
    begin
        @(negedge clk);
        btnC = 1;

        @(negedge clk);
        btnC = 0;

        repeat (3) @(negedge clk);
    end
    endtask

    initial begin

        // Initialize inputs
        reset = 1;
        tick = 0;
        btnC = 0;
        btnD = 0;
        btnL = 0;
        btnR = 0;
        jump = 0;
        practice = 0;
        errors = 0;

        // ----------------------------
        // TEST 1: Reset and MENU
        // ----------------------------

        repeat (2) @(negedge clk);
        reset = 0;
        repeat (3) @(negedge clk);

        $display("TEST 1: Reset");
        $display("state=%d level=%d lives=%d jumps=%d",
                 state, level, lives, jumps);

        if (state !== MENU ||
            level !== 2'd1 ||
            lives !== 4'd9 ||
            jumps !== 14'd0) begin

            $display("FAIL: Incorrect initial game values");
            errors = errors + 1;
        end

        // ----------------------------
        // TEST 2: Start game
        // ----------------------------

        press_center();

        $display("TEST 2: Start game, state=%d", state);

        if (state !== PLAY) begin
            $display("FAIL: Game did not enter PLAY");
            errors = errors + 1;
        end

        // ----------------------------
        // TEST 3: Scrolling
        // ----------------------------

        frame_tick();

        $display("TEST 3: Scrolling, scroll=%d", scroll);

        if (scroll !== 13'd5) begin
            $display("FAIL: Expected scroll=5");
            errors = errors + 1;
        end

        // ----------------------------
        // TEST 4: Jump
        // ----------------------------

        @(negedge clk);
        jump = 1;

        frame_tick();

        @(negedge clk);
        jump = 0;

        $display("TEST 4: Jump");
        $display("runner_h=%d jumps=%d",
                 runner_h, jumps);

        if (runner_h !== 9'd12 ||
            jumps !== 14'd1) begin

            $display("FAIL: Jump did not start correctly");
            errors = errors + 1;
        end

        // ----------------------------
        // TEST 5: Gravity and landing
        // ----------------------------

        for (i = 0; i < 40; i = i + 1)
            frame_tick();

        $display("TEST 5: Gravity and landing");
        $display("runner_h=%d jumps=%d",
                 runner_h, jumps);

        if (runner_h !== 9'd0 ||
            jumps !== 14'd1) begin

            $display("FAIL: Landing or jump count incorrect");
            errors = errors + 1;
        end

        // ----------------------------
        // TEST 6: First spike collision
        // ----------------------------

        // Keep moving without jumping
        // until the first obstacle is reached

        i = 0;

        while (state == PLAY && i < 180) begin
            frame_tick();
            i = i + 1;
        end

        $display("TEST 6: Spike collision");
        $display("state=%d lives=%d scroll=%d",
                 state, lives, scroll);

        if (state !== CRASH || lives !== 4'd8) begin
            $display("FAIL: Expected CRASH with 8 lives");
            errors = errors + 1;
        end

        // ----------------------------
        // Final result
        // ----------------------------

        if (errors == 0)
            $display("ALL TESTS PASSED!");
        else
            $display("TESTS FAILED: %d errors", errors);

        $finish;

    end

endmodule