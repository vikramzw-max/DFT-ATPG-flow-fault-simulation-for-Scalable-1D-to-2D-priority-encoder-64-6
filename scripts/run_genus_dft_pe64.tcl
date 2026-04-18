#=============================================================================
# File        : run_genus_dft_pe64.tcl
# Description : Genus Synthesis + DFT Insertion Script
# Design      : pe64_top (64:6 Scalable Priority Encoder — Pipelined)
# Tool        : Cadence Genus Synthesis Solution  20.1+
# Library     : 90nm (slow.lib)
#
# Execution   : genus -legacy_ui -f run_genus_dft_pe64.tcl
#            OR genus -f run_genus_dft_pe64.tcl  (Stylus Common UI)
#
# Steps performed:
#   1.  Library setup         (90nm slow corner)
#   2.  RTL read & elaborate  (pe64_top.v — all sub-modules included)
#   3.  SDC constraints       (pe64_top.sdc)
#   4.  Pre-synthesis DFT definitions (scan_en, clk_test)
#   5.  Generic synthesis
#   6.  Technology mapping
#   7.  Incremental optimisation
#   8.  Pre-DFT reports + netlist export
#   9.  DFT rules check
#  10.  Scan FF replacement   (DFFQXL -> SDFFQXL)
#  11.  Scan chain connection  (1 chain, 72 FFs)
#  12.  Post-DFT optimisation
#  13.  Post-DFT reports + netlist export
#  14.  ATPG handoff files for Modus
#=============================================================================

puts "============================================================"
puts "  Genus Synthesis + DFT Script for pe64_top"
puts "  Design  : 64:6 Scalable Priority Encoder (Pipelined)"
puts "  Library : 90nm slow corner"
puts "============================================================"

#-----------------------------------------------------------------------------
# Step 1: Library Setup — 90nm foundry (slow corner)
#-----------------------------------------------------------------------------
puts "\n>>> Step 1: Configuring 90nm Library..."
set_db init_lib_search_path /home/install/FOUNDRY/digital/90nm/dig/lib/
set_db library slow.lib

#-----------------------------------------------------------------------------
# Step 2: Read RTL
#   pe64_top.v contains all sub-modules (pe4, pe16, pe64_lookahead,
#   pe64_standard, pe64_top) in a single file for simplicity.
#-----------------------------------------------------------------------------
puts "\n>>> Step 2: Reading RTL Design..."
read_hdl ./pe64_top.v

#-----------------------------------------------------------------------------
# Step 3: Elaborate the top-level module
#-----------------------------------------------------------------------------
puts "\n>>> Step 3: Elaborating Design..."
elaborate pe64_top

# Sanity check: report any unresolved references
check_design -unresolved

#-----------------------------------------------------------------------------
# Step 4: Apply timing constraints (SDC)
#-----------------------------------------------------------------------------
puts "\n>>> Step 4: Reading SDC Timing Constraints..."
read_sdc ./pe64_top.sdc

#-----------------------------------------------------------------------------
# Step 5: Power goals
#-----------------------------------------------------------------------------
set_max_leakage_power 0.0
set_max_dynamic_power 0.0

#-----------------------------------------------------------------------------
# Step 5b: Pre-synthesis DFT definitions
#   MUST be done before syn_map so that Genus maps FFs to scan-capable cells
#   during technology mapping (avoids a second pass to swap cell types).
#-----------------------------------------------------------------------------
puts "\n>>> Step 5b: Defining DFT Scan Infrastructure..."

set_db dft_scan_style muxed_scan
set_db dft_prefix     DFT_

# Shift-enable signal: scan_en port, active-HIGH
define_dft shift_enable -name scan_en_sig -active high scan_en

# Test clock: derives from functional clock 'clk', 10 ns period
define_dft test_clock   -name clk_test    -period 10000 clk

#-----------------------------------------------------------------------------
# Step 6: Generic synthesis  (technology-independent Boolean optimisation)
#-----------------------------------------------------------------------------
puts "\n>>> Step 6: Synthesising to Generic Gates..."
set_db syn_generic_effort high
syn_generic

#-----------------------------------------------------------------------------
# Step 7: Technology mapping  (map to 90nm standard cells)
#-----------------------------------------------------------------------------
puts "\n>>> Step 7: Mapping to 90nm Technology Library..."
set_db syn_map_effort high
syn_map

#-----------------------------------------------------------------------------
# Step 8: Incremental optimisation (timing / area cleanup post-map)
#-----------------------------------------------------------------------------
puts "\n>>> Step 8: Running Incremental Optimisation..."
set_db syn_opt_effort high
syn_opt

#-----------------------------------------------------------------------------
# Step 9: Pre-DFT Reports  (baseline metrics before scan insertion)
#-----------------------------------------------------------------------------
puts "\n>>> Step 9: Generating Pre-DFT Reports..."
report timing > ./pre_dft_timing.rpt
report area   > ./pre_dft_area.rpt
report power  > ./pre_dft_power.rpt
report gates  > ./pre_dft_gates.rpt

puts "  Pre-DFT reports written:"
puts "    pre_dft_timing.rpt  pre_dft_area.rpt"
puts "    pre_dft_power.rpt   pre_dft_gates.rpt"

#-----------------------------------------------------------------------------
# Step 10: Write Pre-DFT Netlist & SDC
#-----------------------------------------------------------------------------
puts "\n>>> Step 10: Writing Pre-DFT Netlist..."
write_hdl > ./pe64_top_pre_dft.v
write_sdc > ./pe64_top_pre_dft.sdc

#-----------------------------------------------------------------------------
# Step 11: DFT Rules Check
#   Verifies that all 72 FFs satisfy DFT controllability / observability rules
#   before scan replacement.  Zero violations expected.
#-----------------------------------------------------------------------------
puts "\n>>> Step 11: Checking DFT Rules (pre-replacement)..."
check_dft_rules > ./dft_rules_check.rpt
puts "  DFT rules report -> dft_rules_check.rpt"
puts "  Expected: 72 registers pass, 0 violations"

#-----------------------------------------------------------------------------
# Step 12: Scan FF Replacement
#   Replaces all 72 DFFQXL / DFFXL cells with muxed-scan SDFFQXL / SDFFXL.
#   Each SDFF adds a 2:1 MUX on the D-input controlled by scan_en.
#
#   Expected scan mapping breakdown:
#     d_s1[63:0]  ->  64 SDFFs  (input pipeline stage)
#     en_s1       ->   1 SDFF   (enable register)
#     q[5:0]      ->   6 SDFFs  (output index stage)
#     v           ->   1 SDFF   (valid flag)
#     Total       ->  72 SDFFs  => 100% scan coverage
#-----------------------------------------------------------------------------
puts "\n>>> Step 12: Replacing Flip-Flops with Scan FFs..."
replace_scan

#-----------------------------------------------------------------------------
# Step 13: Connect Scan Chains
#   Creates a single unified scan chain (chain1) of 72 scan FFs.
#   scan_in  -> [FF_72] -> [FF_71] -> ... -> [FF_1] -> scan_out
#   shift_enable : scan_en (active high)
#   clock domain : clk_test (rising edge)
#-----------------------------------------------------------------------------
puts "\n>>> Step 13: Connecting Scan Chains..."
define_scan_chain -name chain1        \
                  -sdi  scan_in       \
                  -sdo  scan_out      \
                  -non_shared_output

connect_scan_chains
puts "  Scan chain 'chain1' connected: 72 FFs, domain clk_test (rise)"

#-----------------------------------------------------------------------------
# Step 14: Post-DFT Incremental Optimisation
#   Repairs any timing violations introduced by MUX insertion on FF inputs.
#-----------------------------------------------------------------------------
puts "\n>>> Step 14: Post-DFT Incremental Optimisation..."
syn_opt -incr

#-----------------------------------------------------------------------------
# Step 15: Post-DFT Reports  (compare against pre-DFT baseline)
#-----------------------------------------------------------------------------
puts "\n>>> Step 15: Generating Post-DFT Reports..."
report timing              > ./post_dft_timing.rpt
report area                > ./post_dft_area.rpt
report power               > ./post_dft_power.rpt
report gates               > ./post_dft_gates.rpt
report dft_setup           > ./dft_setup.rpt
report dft_chains          > ./scan_chains.rpt
check_dft_rules            > ./post_dft_rules.rpt

puts "  Post-DFT reports written:"
puts "    post_dft_timing.rpt  post_dft_area.rpt"
puts "    post_dft_power.rpt   post_dft_gates.rpt"
puts "    dft_setup.rpt        scan_chains.rpt"
puts "    post_dft_rules.rpt"

#-----------------------------------------------------------------------------
# Step 16: Write Post-DFT Netlist, SDC, SDF, and SCANDEF
#-----------------------------------------------------------------------------
puts "\n>>> Step 16: Writing Post-DFT Netlist and Associated Files..."
write_hdl    > ./pe64_top_post_dft.v
write_sdf    > ./pe64_top_post_dft.sdf
write_sdc    > ./pe64_top_post_dft.sdc
write_scandef > ./pe64_top.scandef

puts "  Post-DFT netlist  -> pe64_top_post_dft.v"
puts "  SDF back-annotation -> pe64_top_post_dft.sdf"
puts "  Post-DFT SDC       -> pe64_top_post_dft.sdc"
puts "  Scan Definition    -> pe64_top.scandef"

#-----------------------------------------------------------------------------
# Step 17: Write ATPG Handoff Files for Cadence Modus
#   Generates:
#     pe64_top.test_netlist.v     — flattened ATPG netlist
#     pe64_top.FULLSCAN.pinassign — pin assignment for test mode
#     pe64_top.FULLSCAN.modedef   — test mode definition
#     pe64_top.FULLSCAN.exclude   — cells/nodes excluded from ATPG
#   These files are consumed by run_modus_atpg_pe64.tcl
#-----------------------------------------------------------------------------
puts "\n>>> Step 17: Writing DFT/ATPG Protocol Files for Modus..."
write_dft_atpg -library ./pe64_top_post_dft.v \
               -directory ./
puts "  Modus input files written to current directory."

#-----------------------------------------------------------------------------
# Final Summary
#-----------------------------------------------------------------------------
puts "\n============================================================"
puts "  Genus Synthesis + DFT Complete!"
puts ""
puts "  Design            : pe64_top (64:6 Priority Encoder)"
puts "  Technology        : 90nm slow corner"
puts "  Scan FFs inserted : 72  (d_s1:64 + en_s1:1 + q:6 + v:1)"
puts "  Scan chains       : 1  (chain1, muxed_scan, clk_test)"
puts "  Scan coverage     : 100% (expected)"
puts ""
puts "  Pre-DFT reports   : pre_dft_*.rpt"
puts "  Post-DFT reports  : post_dft_*.rpt, dft_setup.rpt, scan_chains.rpt"
puts "  Modus ATPG inputs : *.pinassign, *.modedef, *.test_netlist.v"
puts "============================================================"

# Launch Genus GUI for schematic inspection
gui_show
