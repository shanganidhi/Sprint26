`timescale 1ns/1ps
`default_nettype none

//=============================================================================
// tb_systolic_array.sv
// Self-checking SystemVerilog testbench for systolic_array_4x4_pro
//
// Features:
//   - Reads activation & weight matrices from hex files
//   - Computes golden reference (C = A × B) internally
//   - Streams activations in systolic wavefront order
//   - Generates SAIF (via $toggle_*) and VCD for power analysis
//   - Self-checking with PASS/FAIL per output element
//=============================================================================
module tb_systolic_array;

    //=========================================================================
    // Parameters
    //=========================================================================
    parameter DATA_WIDTH = 8;
    parameter ACC_WIDTH  = 32;
    parameter SIZE       = 4;
    parameter CLK_PERIOD = 10; // 100 MHz

    //=========================================================================
    // Clock and Reset
    //=========================================================================
    reg clk;
    reg rst;
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    //=========================================================================
    // DUT signals
    //=========================================================================
    reg                              start;
    reg signed [DATA_WIDTH*SIZE-1:0] activation_bus;
    reg signed [DATA_WIDTH*SIZE-1:0] weight_bus;
    wire signed [ACC_WIDTH*SIZE-1:0] result_bus;
    wire                             done;

    //=========================================================================
    // Test data storage
    //=========================================================================
    reg signed [DATA_WIDTH-1:0] A [0:SIZE-1][0:SIZE-1]; // activations
    reg signed [DATA_WIDTH-1:0] B [0:SIZE-1][0:SIZE-1]; // weights
    integer golden [0:SIZE-1][0:SIZE-1];                  // golden C = A*B

    integer i, j, k;
    integer pass_count, fail_count;

    //=========================================================================
    // DUT instantiation
    //=========================================================================
    systolic_array_4x4_pro #(
        .DATA_WIDTH (DATA_WIDTH),
        .ACC_WIDTH  (ACC_WIDTH),
        .SIZE       (SIZE)
    ) dut (
        .clk           (clk),
        .rst           (rst),
        .start         (start),
        .activation_in (activation_bus),
        .weight_in     (weight_bus),
        .result_out    (result_bus),
        .done          (done)
    );

    //=========================================================================
    // Run-time configurable paths
    //=========================================================================
    string data_dir = "data";
    string test_name = "systolic";

    //=========================================================================
    // Read matrix from hex file (16 values, row-major)
    //=========================================================================
    task automatic read_matrix_hex(
        input string fname,
        output reg signed [DATA_WIDTH-1:0] M [0:SIZE-1][0:SIZE-1]
    );
        integer fd, val, idx, scan_ret;
        string full_path;
        begin
            full_path = {data_dir, "/", fname};
            fd = $fopen(full_path, "r");
            if (fd == 0) begin
                $display("ERROR: Cannot open file %s", full_path);
                $finish;
            end
            idx = 0;
            while (!$feof(fd) && idx < SIZE*SIZE) begin
                scan_ret = $fscanf(fd, "%h\n", val);
                if (scan_ret == 1) begin
                    M[idx / SIZE][idx % SIZE] = val[DATA_WIDTH-1:0];
                    idx = idx + 1;
                end
            end
            $fclose(fd);
            if (idx != SIZE*SIZE) begin
                $display("WARNING: Only read %0d values from %s (expected %0d)", idx, full_path, SIZE*SIZE);
            end
        end
    endtask

    //=========================================================================
    // Compute golden reference: C = A × B
    //=========================================================================
    task automatic compute_golden();
        integer ii, jj, kk;
        integer sum;
        begin
            for (ii = 0; ii < SIZE; ii = ii + 1) begin
                for (jj = 0; jj < SIZE; jj = jj + 1) begin
                    sum = 0;
                    for (kk = 0; kk < SIZE; kk = kk + 1) begin
                        sum = sum + $signed(A[ii][kk]) * $signed(B[kk][jj]);
                    end
                    golden[ii][jj] = sum;
                end
            end
        end
    endtask

    //=========================================================================
    // Pack activation vector for systolic wavefront step
    // At step 's', row 'r' gets column c = s - r (if valid)
    //=========================================================================
    task automatic get_activation_bus(
        input integer step,
        output reg signed [DATA_WIDTH*SIZE-1:0] bus
    );
        integer r, c;
        reg signed [DATA_WIDTH-1:0] tmp [0:SIZE-1];
        begin
            for (r = 0; r < SIZE; r = r + 1) begin
                c = step - r;
                if (c >= 0 && c < SIZE)
                    tmp[r] = A[r][c];
                else
                    tmp[r] = {DATA_WIDTH{1'b0}};
            end
            bus = {tmp[3], tmp[2], tmp[1], tmp[0]};
        end
    endtask

    //=========================================================================
    // Pack weight column vector
    //=========================================================================
    task automatic get_weight_bus(
        input integer col,
        output reg signed [DATA_WIDTH*SIZE-1:0] bus
    );
        integer r;
        reg signed [DATA_WIDTH-1:0] tmp [0:SIZE-1];
        begin
            for (r = 0; r < SIZE; r = r + 1)
                tmp[r] = B[r][col];
            bus = {tmp[3], tmp[2], tmp[1], tmp[0]};
        end
    endtask

    //=========================================================================
    // Run one complete matrix multiply experiment
    //=========================================================================
    task automatic run_experiment();
        integer step;
        integer timeout;
        begin
            $display("---------------------------------------------------");
            $display("Starting experiment...");
            $display("---------------------------------------------------");

            // Print input matrices
            $display("Matrix A (activations):");
            for (i = 0; i < SIZE; i = i + 1)
                $display("  [%4d %4d %4d %4d]",
                    $signed(A[i][0]), $signed(A[i][1]),
                    $signed(A[i][2]), $signed(A[i][3]));

            $display("Matrix B (weights):");
            for (i = 0; i < SIZE; i = i + 1)
                $display("  [%4d %4d %4d %4d]",
                    $signed(B[i][0]), $signed(B[i][1]),
                    $signed(B[i][2]), $signed(B[i][3]));

            $display("Golden C = A*B:");
            for (i = 0; i < SIZE; i = i + 1)
                $display("  [%6d %6d %6d %6d]",
                    golden[i][0], golden[i][1],
                    golden[i][2], golden[i][3]);

            // Reset
            rst = 1;
            start = 0;
            activation_bus = {DATA_WIDTH*SIZE{1'b0}};
            weight_bus = {DATA_WIDTH*SIZE{1'b0}};
            repeat(4) @(posedge clk);
            rst = 0;
            repeat(2) @(posedge clk);

            // PHASE 1: Load weights (one column per cycle)
            start = 1;
            @(posedge clk);

            for (i = 0; i < SIZE; i = i + 1) begin
                get_weight_bus(i, weight_bus);
                @(posedge clk);
            end

            start = 0;
            weight_bus = {DATA_WIDTH*SIZE{1'b0}};

            // Wait for controller to enter COMPUTE state
            repeat(2) @(posedge clk);

            // PHASE 2: Stream activations (wavefront pattern)
            for (step = 0; step < (2*SIZE - 1); step = step + 1) begin
                get_activation_bus(step, activation_bus);
                @(posedge clk);
            end
            activation_bus = {DATA_WIDTH*SIZE{1'b0}};

            // PHASE 3: Wait for done signal (with timeout)
            timeout = 0;
            while (!done && timeout < 100) begin
                @(posedge clk);
                timeout = timeout + 1;
            end

            if (timeout >= 100) begin
                $display("ERROR: Timeout waiting for done signal!");
                fail_count = fail_count + SIZE*SIZE;
                return;
            end

            $display("Computation completed (done asserted after %0d extra cycles)", timeout);

            // Check results (bottom row psum outputs)
            // Note: In weight-stationary systolic array, the result extraction
            // depends on architecture. We check the result_out bus.
            $display("Checking results...");
            for (j = 0; j < SIZE; j = j + 1) begin
                integer got;
                got = $signed(result_bus[ACC_WIDTH*(j+1)-1 -: ACC_WIDTH]);
                // Bottom row results correspond to row SIZE-1 of golden
                if (got == golden[SIZE-1][j]) begin
                    $display("  PASS: result[%0d] = %0d (golden = %0d)", j, got, golden[SIZE-1][j]);
                    pass_count = pass_count + 1;
                end else begin
                    $display("  FAIL: result[%0d] = %0d (golden = %0d)", j, got, golden[SIZE-1][j]);
                    fail_count = fail_count + 1;
                end
            end
        end
    endtask

    //=========================================================================
    // Main test sequence
    //=========================================================================
    initial begin
        string vcd_path;
        string saif_path;

        if ($value$plusargs("DATA_DIR=%s", data_dir)) begin
            $display("Using custom DATA_DIR: %s", data_dir);
        end
        if ($value$plusargs("TEST_NAME=%s", test_name)) begin
            $display("Using custom TEST_NAME: %s", test_name);
        end

        vcd_path = {"waves/", test_name, ".vcd"};
        saif_path = {"waves/", test_name, ".saif"};

        // VCD dump
        $dumpfile(vcd_path);
        $dumpvars(0, tb_systolic_array);

        // SAIF toggle collection (Xcelium)
        `ifdef XCELIUM
            $set_toggle_region("tb_systolic_array.dut");
            $toggle_start();
        `endif

        pass_count = 0;
        fail_count = 0;

        // Read test data
        $display("Loading test data from %s...", data_dir);
        read_matrix_hex("activations.hex", A);
        read_matrix_hex("weights.hex", B);
        compute_golden();

        // Run the experiment
        run_experiment();

        // Small gap
        repeat(10) @(posedge clk);

        // SAIF dump (Xcelium)
        `ifdef XCELIUM
            $toggle_stop();
            $toggle_report(saif_path, 1.0e-9, "tb_systolic_array.dut");
            $display("SAIF written to %s", saif_path);
        `endif

        // Summary
        $display("===================================================");
        $display("TEST SUMMARY: %0d PASS, %0d FAIL", pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED!");
        else
            $display("SOME TESTS FAILED!");
        $display("===================================================");

        #20;
        $finish;
    end

    // Timeout watchdog
    initial begin
        #50000;
        $display("GLOBAL TIMEOUT — simulation forcefully terminated");
        $finish;
    end

endmodule

`default_nettype wire
