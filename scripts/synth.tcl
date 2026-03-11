###############################################################
# Cadence Genus Synthesis Script
# Project  : Low-Power 4x4 INT8 Systolic Array
# Top      : systolic_array_4x4_pro
#
# Usage:
#   genus -f synth.tcl                         # functional synthesis
#   SAIF_FILE=waves/dense.saif genus -f synth.tcl  # with switching activity
###############################################################

set PROJECT_DIR [file normalize [file dirname [info script]]/..]
set RTL_DIR     $PROJECT_DIR/rtl
set REPORT_DIR  $PROJECT_DIR/reports
set NETLIST_DIR $PROJECT_DIR/netlist
file mkdir $REPORT_DIR
file mkdir $NETLIST_DIR

set TOP_MODULE systolic_array_4x4_pro

###############################################################
# Libraries — Update these paths to match YOUR environment
###############################################################
# Option 1: Foundry 45nm max/min libraries
set LIB_MAX_DIR /home/install/FOUNDRY/digital/45nm/LIBS/lib/max
set LIB_MIN_DIR /home/install/FOUNDRY/digital/45nm/LIBS/lib/min

# Option 2: FreePDK45 / Nangate (fallback)
set LIB_NANGATE /home/install/IC618/RA2311067010024/FOUNDRY/digital/45nm/NangateOpenCellLibrary_v1.00_20080225/liberty/FreePDK45_lib_v1.0_typical.lib

# Try max/min first, fallback to Nangate
set libs_loaded 0
foreach libdir [list $LIB_MAX_DIR $LIB_MIN_DIR] {
    if {[file isdirectory $libdir]} {
        foreach libfile [glob -nocomplain $libdir/*.lib] {
            puts "Reading library: $libfile"
            read_libs $libfile
            set libs_loaded 1
        }
    }
}
if {!$libs_loaded && [file exists $LIB_NANGATE]} {
    puts "Using Nangate library: $LIB_NANGATE"
    read_libs $LIB_NANGATE
}

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
# Design checks
###############################################################
check_design > $REPORT_DIR/check_design.rpt

###############################################################
# Timing Constraints
###############################################################
create_clock -name clk -period 10 [get_ports clk]
set_input_delay  1 -clock clk [all_inputs -no_clocks]
set_output_delay 1 -clock clk [all_outputs]
set_clock_uncertainty 0.1 [get_clocks clk]

###############################################################
# Power-Aware Synthesis Settings
###############################################################
set_db syn_global_effort high
set_db syn_map_effort    high
set_db syn_opt_effort    high

# Clock gating insertion (if library contains ICG cells)
set_db lp_insert_clock_gating       true
set_db lp_clock_gating_prefix       CG_
set_db lp_clock_gating_min_flops    2
set_db lp_clock_gating_sequential   true

###############################################################
# Read SAIF switching activity (if provided via env var)
###############################################################
if {[info exists ::env(SAIF_FILE)]} {
    set saif_path $::env(SAIF_FILE)
    puts "Reading SAIF: $saif_path"
    if {[file exists $saif_path]} {
        read_saif $saif_path -instance $TOP_MODULE
    } else {
        puts "WARNING: SAIF file not found: $saif_path"
    }
} else {
    puts "No SAIF_FILE env var — running functional synthesis only"
}

###############################################################
# Synthesis
###############################################################
syn_generic
syn_map
syn_opt

###############################################################
# Reports
###############################################################
report_area                    > $REPORT_DIR/area_report.rpt
report_timing                  > $REPORT_DIR/timing_report.rpt
report_power                   > $REPORT_DIR/power_report.rpt
report_power -by_hierarchy     > $REPORT_DIR/power_by_hierarchy.rpt

# Clock gating summary (if available)
catch {report_clock_gating     > $REPORT_DIR/clock_gating.rpt}

###############################################################
# Write Netlist and DB
###############################################################
write_hdl -mapped              > $NETLIST_DIR/systolic_array_netlist.v
write_db                         $NETLIST_DIR/systolic_array.db

puts "============================================="
puts "Synthesis complete. Reports: $REPORT_DIR"
puts "============================================="
exit
