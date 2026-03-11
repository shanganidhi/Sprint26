# design.sdc — Timing constraints for systolic_array_4x4_pro
# Target: 100 MHz (10 ns period) on 45nm process

# Clock definition
create_clock -name clk -period 10 [get_ports clk]

# Clock uncertainty (jitter + skew)
set_clock_uncertainty 0.1 [get_clocks clk]

# Input delays (relative to clock)
set_input_delay  1.0 -clock clk [all_inputs -no_clocks]

# Output delays (relative to clock)
set_output_delay 1.0 -clock clk [all_outputs]

# Drive strength and load (reasonable defaults for 45nm)
# set_driving_cell -lib_cell BUFX2 [all_inputs]
# set_load 0.01 [all_outputs]
