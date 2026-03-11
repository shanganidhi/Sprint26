###############################################################
# Cadence Genus Synthesis Script
# Project : Low-Power 4x4 INT8 Systolic Array
# Top     : systolic_array_4x4_pro
###############################################################

###############################################################
# Paths
###############################################################

set PROJECT_DIR /home/install/IC618/RA2311067010024/pro
set RTL_DIR     $PROJECT_DIR/rtl
set REPORT_DIR  $PROJECT_DIR/reports
set NETLIST_DIR $PROJECT_DIR/netlist

file mkdir $REPORT_DIR
file mkdir $NETLIST_DIR

set TOP_MODULE systolic_array_4x4_pro


###############################################################
# Technology Library
###############################################################

set LIB_FILE /home/install/FOUNDRY/digital/45nm/LIBS/lib/max/slow.lib

read_libs $LIB_FILE


###############################################################
# Synthesis effort
###############################################################

set_db syn_global_effort high
set_db syn_map_effort high
set_db syn_opt_effort high


###############################################################
# Clock gating (must be before elaboration)
###############################################################

set_db lp_insert_clock_gating true
set_db lp_clock_gating_prefix CG_


###############################################################
# Read RTL
###############################################################

read_hdl $RTL_DIR/pe_ws_pro.v
read_hdl $RTL_DIR/localized_controller_pro.v
read_hdl $RTL_DIR/wavefront_controller.v
read_hdl $RTL_DIR/systolic_array_4x4_pro.v


###############################################################
# Elaborate
###############################################################

elaborate $TOP_MODULE


###############################################################
# Check design
###############################################################

check_design > $REPORT_DIR/check_design.rpt


###############################################################
# Timing constraints
###############################################################

create_clock -name clk -period 10 [get_ports clk]

set_input_delay 1 -clock clk [all_inputs -no_clocks]
set_output_delay 1 -clock clk [all_outputs]

set_clock_uncertainty 0.1 [get_clocks clk]


###############################################################
# Synthesis
###############################################################

syn_generic
syn_map
syn_opt


###############################################################
# Reports
###############################################################

report_area  > $REPORT_DIR/area_report.rpt
report_timing > $REPORT_DIR/timing_report.rpt
report_power > $REPORT_DIR/power_report.rpt
report_power -by_hierarchy > $REPORT_DIR/power_by_hierarchy.rpt

catch {report_clock_gating > $REPORT_DIR/clock_gating.rpt}


###############################################################
# Outputs
###############################################################

write_hdl -mapped > $NETLIST_DIR/systolic_array_netlist.v
write_db $NETLIST_DIR/systolic_array.db


###############################################################
# Done
###############################################################

puts "============================================="
puts "Synthesis completed successfully"
puts "Reports available in $REPORT_DIR"
puts "============================================="

exit
