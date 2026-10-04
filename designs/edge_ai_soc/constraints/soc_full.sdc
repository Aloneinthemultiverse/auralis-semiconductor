# Edge-AI SoC top-level timing constraints (SDC) - 1 GHz core clock, 28 nm target.
# Foundry/sign-off flows: add the library-specific clock uncertainty and derates from the PDK.
current_design soc_full

set CLK_PERIOD 1.0
create_clock -name core_clk -period $CLK_PERIOD [get_ports clk]
set_clock_uncertainty -setup 0.050 [get_clocks core_clk]
set_clock_uncertainty -hold  0.020 [get_clocks core_clk]
set_clock_transition 0.040 [get_clocks core_clk]

# Asynchronous power-on reset: synchronised inside (rst_sync), not a timing path
set_false_path -from [get_ports por_n]

# Static fuse / strap / channel-model inputs (OTP is read once, before CPUs leave reset)
set_false_path -from [get_ports {otp_digest[*] otp_min_version[*] eye_lo[*] temp[*]}]

# Off-chip interfaces are synchronous to core_clk at this boundary (the PHY/flash controller/peripheral
# subsystem hard macros own the real pad timing). Budget 30 % of the cycle on each side.
set IO_BUDGET [expr 0.3 * $CLK_PERIOD]
set sync_in  [get_ports {fl_gnt fl_rvalid fl_rdata[*] fl_err d_rd_valid d_rd_data[*] per_gnt per_rvalid per_rdata[*] pwr_ack[*]}]
set sync_out [get_ports {fl_req fl_addr[*] d_cmd_valid d_cmd[*] d_bank[*] d_row[*] d_col[*] d_mrw[*] d_wr_valid d_wr_data[*] d_wr_dm[*] per_req per_we per_addr[*] per_wdata[*] pwr_en[*] sys_reset_req ddr_ready}]
set_input_delay  $IO_BUDGET -clock core_clk $sync_in
set_output_delay $IO_BUDGET -clock core_clk $sync_out
set_load 0.010 [all_outputs]
set_driving_cell -lib_cell BUF_X2 [remove_from_collection [all_inputs] [get_ports clk]]

# Multicycle: the PMU temperature compare and watchdog counter reload are not single-cycle critical
set_multicycle_path -setup 2 -through [get_pins -hierarchical *u_pmu*temp_th*]
set_multicycle_path -hold  1 -through [get_pins -hierarchical *u_pmu*temp_th*]
