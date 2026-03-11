`timescale 1ns/1ps
`default_nettype none

//=============================================================================
// wavefront_controller.v
// TPU-style Diagonal Wavefront Controller
//
// Generates per-PE enable signals based on the systolic wavefront pattern:
//   PE(r,c) active when: cycle >= r+c AND cycle < r+c+SIZE
//
// This ensures only a subset of PEs toggle each cycle, reducing switching.
//
// Wavefront pattern for 4×4 array:
//   Cycle 0: (0,0)
//   Cycle 1: (0,1) (1,0)
//   Cycle 2: (0,2) (1,1) (2,0)
//   Cycle 3: (0,3) (1,2) (2,1) (3,0)   ← full diagonal
//   Cycle 4: (1,3) (2,2) (3,1)
//   Cycle 5: (2,3) (3,2)
//   Cycle 6: (3,3)
//=============================================================================
module wavefront_controller #(
    parameter SIZE      = 4,
    parameter CNT_WIDTH = 8
)(
    input  wire                   clk,
    input  wire                   rst,
    input  wire                   start,    // begin counting when asserted
    input  wire                   clear,    // reset cycle counter

    output reg  [CNT_WIDTH-1:0]  cycle,    // current wavefront cycle

    // Flattened PE enable array: pe_enable[row*SIZE + col]
    output wire [SIZE*SIZE-1:0]  pe_enable
);

    //=========================================================================
    // Cycle counter — counts when start is asserted
    //=========================================================================
    always @(posedge clk) begin
        if (rst || clear)
            cycle <= {CNT_WIDTH{1'b0}};
        else if (start)
            cycle <= cycle + 1'b1;
    end

    //=========================================================================
    // Generate PE enable signals for diagonal wavefront
    // PE(r,c) is active when: cycle >= (r+c) AND cycle < (r+c+SIZE)
    //=========================================================================
    genvar r, c;
    generate
        for (r = 0; r < SIZE; r = r + 1) begin : gen_row
            for (c = 0; c < SIZE; c = c + 1) begin : gen_col
                assign pe_enable[r*SIZE + c] =
                    (cycle >= (r + c)) && (cycle < (r + c + SIZE));
            end
        end
    endgenerate

endmodule

`default_nettype wire
