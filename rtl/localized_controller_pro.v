`timescale 1ns/1ps
`default_nettype none

//=============================================================================
// localized_controller_pro.v
// Controls weight load / compute / flush phases.
// Provides a cycle counter for wavefront PE scheduling.
//
// State Machine:
//   IDLE → LOAD_WEIGHT → COMPUTE → FLUSH → FINISH → IDLE
//
// The 'cycle' output drives PE wavefront enable logic in the top module.
//=============================================================================
module localized_controller_pro #(
    parameter SIZE      = 4,
    parameter CNT_WIDTH = 8
)(
    input  wire                   clk,
    input  wire                   rst,
    input  wire                   start,

    output reg                    weight_load,
    output reg                    acc_clear,
    output reg                    valid_in,
    output reg                    done,
    output reg  [CNT_WIDTH-1:0]  cycle
);

    //=========================================================================
    // State encoding
    //=========================================================================
    localparam [2:0] IDLE        = 3'b000,
                     LOAD_WEIGHT = 3'b001,
                     COMPUTE     = 3'b010,
                     FLUSH       = 3'b011,
                     FINISH      = 3'b100;

    reg [2:0] state, next_state;
    reg [CNT_WIDTH-1:0] counter;

    //=========================================================================
    // Next-state combinational logic
    //=========================================================================
    always @(*) begin
        next_state = state;
        case (state)
            IDLE:        if (start)                        next_state = LOAD_WEIGHT;
            LOAD_WEIGHT: if (counter == SIZE - 1)          next_state = COMPUTE;
            COMPUTE:     if (counter == (SIZE + SIZE - 2)) next_state = FLUSH;
            FLUSH:       if (counter == SIZE - 1)          next_state = FINISH;
            FINISH:                                        next_state = IDLE;
            default:                                       next_state = IDLE;
        endcase
    end

    //=========================================================================
    // State register and counters
    //=========================================================================
    always @(posedge clk) begin
        if (rst) begin
            state   <= IDLE;
            counter <= {CNT_WIDTH{1'b0}};
            cycle   <= {CNT_WIDTH{1'b0}};
        end else begin
            state <= next_state;

            // Reset counter on state transition, otherwise increment
            if (state != next_state)
                counter <= {CNT_WIDTH{1'b0}};
            else
                counter <= counter + 1'b1;

            // Global cycle counter — increments during COMPUTE and FLUSH
            // This drives the wavefront scheduling logic
            if (next_state == LOAD_WEIGHT)
                cycle <= {CNT_WIDTH{1'b0}};
            else if (next_state == COMPUTE || next_state == FLUSH)
                cycle <= cycle + 1'b1;
        end
    end

    //=========================================================================
    // Output logic
    //=========================================================================
    always @(posedge clk) begin
        if (rst) begin
            weight_load <= 1'b0;
            acc_clear   <= 1'b0;
            valid_in    <= 1'b0;
            done        <= 1'b0;
        end else begin
            // defaults
            weight_load <= 1'b0;
            acc_clear   <= 1'b0;
            valid_in    <= 1'b0;
            done        <= 1'b0;

            case (state)
                IDLE: begin
                    acc_clear <= 1'b1; // clear accumulators before start
                end
                LOAD_WEIGHT: begin
                    weight_load <= 1'b1;
                end
                COMPUTE: begin
                    valid_in <= 1'b1;
                end
                FLUSH: begin
                    valid_in <= 1'b0; // no new activations during flush
                end
                FINISH: begin
                    done <= 1'b1;
                end
            endcase
        end
    end

endmodule

`default_nettype wire
