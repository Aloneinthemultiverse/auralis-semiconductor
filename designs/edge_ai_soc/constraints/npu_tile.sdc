# NPU tile (R x C systolic array + tiler + pipelined requantizer) - standalone IP delivery.
current_design npu_tile
set CLK_PERIOD 1.0
create_clock -name core_clk -period $CLK_PERIOD [get_ports clk]
set_clock_uncertainty -setup 0.050 [get_clocks core_clk]
set_false_path -from [get_ports rst_n]
set_input_delay  [expr 0.3 * $CLK_PERIOD] -clock core_clk [remove_from_collection [all_inputs] [get_ports {clk rst_n}]]
set_output_delay [expr 0.3 * $CLK_PERIOD] -clock core_clk [all_outputs]
