# Cleave RV32I — timing constraint for OpenSTA (functional PoC, loose period)
create_clock -name clk -period 40.000 [get_ports clk]
set_clock_uncertainty 0.25 [get_clocks clk]
set_input_delay  2.0 -clock clk [remove_from_collection [all_inputs]  [get_ports clk]]
set_output_delay 2.0 -clock clk [all_outputs]
