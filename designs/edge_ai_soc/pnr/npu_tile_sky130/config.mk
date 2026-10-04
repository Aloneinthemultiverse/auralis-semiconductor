export DESIGN_NAME = npu_tile
export PLATFORM    = sky130hd
export VERILOG_FILES = /work/rtl/ram_1r1w.sv /work/rtl/npu_pe.sv /work/rtl/npu_array.sv /work/rtl/npu_core.sv /work/rtl/npu_tile.sv
export SDC_FILE      = /work/pnr/npu_tile_sky130/constraint.sdc
export CORE_UTILIZATION ?= 40
export PLACE_DENSITY_LB_ADDON = 0.15
export TNS_END_PERCENT = 100
