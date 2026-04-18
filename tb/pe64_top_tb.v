`timescale 1ns/1ps
//=============================================================================
// File        : pe64_top_tb.v
// Description : Functional verification testbench for pe64_top
//               Covers: directed corner cases, walking-1, walking-0,
//                       multi-bit, boundary, and reset tests.
//
// Pipeline latency: 2 clock cycles  (input register → output register)
// Clock            : 100 MHz  (10 ns period)
//=============================================================================

module pe64_top_tb;

    // -------------------------------------------------------------------------
    // DUT signal declarations
    // -------------------------------------------------------------------------
    reg        clk;
    reg        rst_n;
    reg        enable;
    reg [63:0] d;
    reg        scan_en;
    reg        scan_in;

    wire [5:0] q;
    wire       v;
    wire       scan_out;

    // -------------------------------------------------------------------------
    // Clock generation : 100 MHz  (10 ns period)
    // -------------------------------------------------------------------------
    initial clk = 1'b0;
    always  #5 clk = ~clk;

    // -------------------------------------------------------------------------
    // DUT instantiation
    // -------------------------------------------------------------------------
    pe64_top dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .enable   (enable),
        .d        (d),
        .q        (q),
        .v        (v),
        .scan_en  (scan_en),
        .scan_in  (scan_in),
        .scan_out (scan_out)
    );

    // -------------------------------------------------------------------------
    // Task : apply_test
    //   Drives d + enable for 2 clock cycles to propagate through the 2-stage
    //   pipeline, then samples and displays the result.
    //   Pipeline stages:
    //     posedge +1 : d_s1 <= d , en_s1 <= 1
    //     posedge +2 : q    <= q_comb  (valid output)
    // -------------------------------------------------------------------------
    integer pass_count;
    integer fail_count;

    task apply_test;
        input [63:0]   in_d;
        input [5:0]    exp_q;
        input          exp_v;
        input [7:0]    test_id;
        reg   [63:0]   captured_d;
        begin
            captured_d = in_d;

            // Drive input before first active edge
            @(negedge clk);
            d      = captured_d;
            enable = 1'b1;

            @(posedge clk); // stage 1 captures: d_s1 = captured_d, en_s1 = 1
            @(posedge clk); // stage 2 captures: q = q_comb, v = v_comb
            #1;             // allow registered output to settle

            if (q === exp_q && v === exp_v) begin
                $display("[TEST %0d] PASS | d=64'h%016h => q=%2d, v=%b",
                          test_id, captured_d, q, v);
                pass_count = pass_count + 1;
            end else begin
                $display("[TEST %0d] FAIL | d=64'h%016h => q=%2d (exp %2d), v=%b (exp %b)",
                          test_id, captured_d, q, exp_q, v, exp_v);
                fail_count = fail_count + 1;
            end

            // De-assert enable and flush pipeline
            @(negedge clk);
            enable = 1'b0;
            @(posedge clk); // en_s1 goes low
            @(posedge clk); // v goes low — pipeline clean
        end
    endtask

    // -------------------------------------------------------------------------
    // Stimulus
    // -------------------------------------------------------------------------
    integer i;
    reg [63:0] walk_vec;

    initial begin
        // --- Initialise ---
        rst_n    = 1'b0;
        enable   = 1'b0;
        d        = 64'b0;
        scan_en  = 1'b0;
        scan_in  = 1'b0;
        pass_count = 0;
        fail_count = 0;

        // Assert reset for 4 cycles
        repeat(4) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        repeat(2) @(posedge clk);

        $display("======================================================================");
        $display(" 64:6 Priority Encoder (pe64_top) — Functional Verification");
        $display("======================================================================");

        // -----------------------------------------------------------------------
        // Section A: Boundary / Corner Cases
        // -----------------------------------------------------------------------
        $display("\n--- Section A: Boundary and Corner Cases ---");

        // Test 1: All zeros — no valid output
        apply_test(64'h0000000000000000, 6'd0,  1'b0,  1);

        // Test 2: Only bit 0 set — lowest priority
        apply_test(64'h0000000000000001, 6'd0,  1'b1,  2);

        // Test 3: Only bit 1 set
        apply_test(64'h0000000000000002, 6'd1,  1'b1,  3);

        // Test 4: Only bit 3 set (MSB of group 0)
        apply_test(64'h0000000000000008, 6'd3,  1'b1,  4);

        // Test 5: Only bit 4 set (LSB of group 1)
        apply_test(64'h0000000000000010, 6'd4,  1'b1,  5);

        // Test 6: Only bit 7 set
        apply_test(64'h0000000000000080, 6'd7,  1'b1,  6);

        // Test 7: Only bit 15 set (group 3 MSB)
        apply_test(64'h0000000000008000, 6'd15, 1'b1,  7);

        // Test 8: Only bit 31 set (lower-half MSB)
        apply_test(64'h0000000080000000, 6'd31, 1'b1,  8);

        // Test 9: Only bit 32 set (upper-half LSB)
        apply_test(64'h0000000100000000, 6'd32, 1'b1,  9);

        // Test 10: Only bit 59 set
        apply_test(64'h0800000000000000, 6'd59, 1'b1, 10);

        // Test 11: Only bit 63 set — highest priority
        apply_test(64'h8000000000000000, 6'd63, 1'b1, 11);

        // Test 12: All ones — highest priority wins (bit 63)
        apply_test(64'hFFFFFFFFFFFFFFFF, 6'd63, 1'b1, 12);

        // -----------------------------------------------------------------------
        // Section B: Multi-bit Arbitration
        // -----------------------------------------------------------------------
        $display("\n--- Section B: Multi-bit Priority Arbitration ---");

        // Test 13: bit 63 and bit 0 — bit 63 must win
        apply_test(64'h8000000000000001, 6'd63, 1'b1, 13);

        // Test 14: bit 47 and bit 20 — bit 47 must win
        apply_test(64'h0000800000100000, 6'd47, 1'b1, 14);

        // Test 15: bit 5 and bit 3 — bit 5 must win
        apply_test(64'h0000000000000028, 6'd5,  1'b1, 15);

        // Test 16: bit 35 is MSB of group 8 (d[35:32]) with bit 32 also set
        apply_test(64'h0000000F00000000, 6'd35, 1'b1, 16);

        // Test 17: bits 16, 17, 18, 19 set — bit 19 must win
        apply_test(64'h00000000000F0000, 6'd19, 1'b1, 17);

        // Test 18: all bits in upper 32 set, all lower 32 clear
        apply_test(64'hFFFFFFFF00000000, 6'd63, 1'b1, 18);

        // Test 19: all bits in lower 32 set, all upper 32 clear
        apply_test(64'h00000000FFFFFFFF, 6'd31, 1'b1, 19);

        // Test 20: alternating nibbles set in upper half
        apply_test(64'hF0F0F0F000000000, 6'd63, 1'b1, 20);

        // -----------------------------------------------------------------------
        // Section C: Walking-1 (all 64 bit positions)
        // -----------------------------------------------------------------------
        $display("\n--- Section C: Walking '1' Test (bit 0 to bit 63) ---");

        for (i = 0; i < 64; i = i + 1) begin
            walk_vec = (64'h0000000000000001 << i);

            @(negedge clk);
            d      = walk_vec;
            enable = 1'b1;
            @(posedge clk);   // stage 1
            @(posedge clk);   // stage 2 — output valid
            #1;

            if (q === i[5:0] && v === 1'b1) begin
                pass_count = pass_count + 1;
                // Only print failures in walking test for brevity
            end else begin
                $display("[WALK-1 bit %2d] FAIL | q=%2d (exp %2d), v=%b (exp 1)",
                          i, q, i[5:0], v);
                fail_count = fail_count + 1;
            end

            @(negedge clk);
            enable = 1'b0;
            @(posedge clk);
            @(posedge clk);
        end
        $display("  Walking-1 complete: 64 tests  (failures shown above)");

        // -----------------------------------------------------------------------
        // Section D: Walking-0 (single bit cleared, all others set)
        // -----------------------------------------------------------------------
        $display("\n--- Section D: Walking '0' Test (bit 63 clear walks down) ---");

        for (i = 63; i >= 0; i = i - 1) begin
            walk_vec = ~(64'h0000000000000001 << i);

            @(negedge clk);
            d      = walk_vec;
            enable = 1'b1;
            @(posedge clk);
            @(posedge clk);
            #1;

            // Expected: highest set bit is (63) unless i==63; then (62), etc.
            begin : walk0_check
                integer exp_idx;
                exp_idx = (i == 63) ? 62 : 63;
                if (v === 1'b1 && q === exp_idx[5:0]) begin
                    pass_count = pass_count + 1;
                end else begin
                    $display("[WALK-0 bit %2d] FAIL | q=%2d (exp %2d), v=%b",
                              i, q, exp_idx[5:0], v);
                    fail_count = fail_count + 1;
                end
            end

            @(negedge clk);
            enable = 1'b0;
            @(posedge clk);
            @(posedge clk);
        end
        $display("  Walking-0 complete: 64 tests  (failures shown above)");

        // -----------------------------------------------------------------------
        // Section E: Reset Verification
        // -----------------------------------------------------------------------
        $display("\n--- Section E: Reset Verification ---");

        // Load some valid data first
        @(negedge clk);
        d      = 64'hDEADBEEFCAFEBABE;
        enable = 1'b1;
        repeat(3) @(posedge clk);
        #1;
        $display("[RESET-PRE ] q=%2d, v=%b (should be non-zero)", q, v);

        // Apply reset while data is loaded
        @(negedge clk);
        rst_n  = 1'b0;
        enable = 1'b0;
        repeat(3) @(posedge clk);
        #1;
        if (q === 6'b0 && v === 1'b0) begin
            $display("[RESET-POST] PASS | q=%2d, v=%b  (both cleared)", q, v);
            pass_count = pass_count + 1;
        end else begin
            $display("[RESET-POST] FAIL | q=%2d (exp 0), v=%b (exp 0)", q, v);
            fail_count = fail_count + 1;
        end
        @(negedge clk);
        rst_n = 1'b1;

        // -----------------------------------------------------------------------
        // Section F: Enable-gating check
        // -----------------------------------------------------------------------
        $display("\n--- Section F: Enable-Gating Check ---");

        // Apply data without enable — output should stay unchanged (v=0)
        @(negedge clk);
        d      = 64'hFFFFFFFFFFFFFFFF;
        enable = 1'b0;
        repeat(3) @(posedge clk);
        #1;
        if (v === 1'b0) begin
            $display("[ENABLE-GATE] PASS | enable=0 => v=%b (gate holds)", v);
            pass_count = pass_count + 1;
        end else begin
            $display("[ENABLE-GATE] FAIL | enable=0 but v=%b (expected 0)", v);
            fail_count = fail_count + 1;
        end

        // -----------------------------------------------------------------------
        // Summary
        // -----------------------------------------------------------------------
        $display("\n======================================================================");
        $display("  Testbench Complete");
        $display("  Total PASS : %0d", pass_count);
        $display("  Total FAIL : %0d", fail_count);
        $display("======================================================================\n");

        if (fail_count == 0)
            $display("*** ALL TESTS PASSED — 0 mismatches ***\n");
        else
            $display("*** %0d TEST(S) FAILED — check log above ***\n", fail_count);

        #100;
        $finish;
    end

    // Waveform dump (for NCLaunch / SimVision)
    initial begin
        $dumpfile("pe64_top_tb.vcd");
        $dumpvars(0, pe64_top_tb);
    end

endmodule
