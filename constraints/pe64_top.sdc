#=============================================================================
# File        : pe64_top.sdc
# Description : Timing Constraints for 64:6 Pipelined Priority Encoder
# Target      : 100 MHz  (10 ns period)  |  90nm slow corner library
#
# Critical path analysis:
#   Launch FF  (CK->Q)  ~0.20 ns
#   pe64_lookahead comb ~3.50 ns  (OR tree + casex MUX + pe4 column)
#   Setup margin        ~0.17 ns
#   Estimated path      ~3.87 ns  =>  slack > 5 ns at 10 ns period
#=============================================================================

#-----------------------------------------------------------------------------
# Primary clock definition
#-----------------------------------------------------------------------------
create_clock -name clk -period 10.0 [get_ports clk]

# Clock quality attributes
set_clock_transition  0.10 [all_clocks]
set_clock_uncertainty -setup 0.30 [all_clocks]
set_clock_uncertainty -hold  0.10 [all_clocks]

#-----------------------------------------------------------------------------
# Input / Output delays  (relative to rising clock edge)
#-----------------------------------------------------------------------------
# Functional data and control inputs: 2 ns before clock capture edge
set_input_delay 2.0 -clock clk [get_ports {d[*] enable rst_n}]

# DFT scan ports: no functional delay constraint (DFT tool controls timing)
set_input_delay 0.0 -clock clk [get_ports {scan_in scan_en}]

# Outputs: must be stable 2 ns after clock edge for downstream registers
set_output_delay 2.0 -clock clk [get_ports {q[*] v scan_out}]

#-----------------------------------------------------------------------------
# False paths on asynchronous-style DFT ports
# (Genus will override / extend these during DFT insertion if needed)
#-----------------------------------------------------------------------------
set_false_path -from [get_ports scan_en]
set_false_path -from [get_ports scan_in]
set_false_path -to   [get_ports scan_out]

#-----------------------------------------------------------------------------
# Driving cell / load assumptions  (typical for 90nm IO estimation)
#-----------------------------------------------------------------------------
set_driving_cell  -lib_cell INVX1 -pin Y [get_ports {d[*] enable}]
set_load          0.05              [all_outputs]

#-----------------------------------------------------------------------------
# Operating conditions
#-----------------------------------------------------------------------------
set_operating_conditions -library slow slow

