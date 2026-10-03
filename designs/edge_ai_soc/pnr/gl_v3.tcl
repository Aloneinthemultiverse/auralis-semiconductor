read_liberty /OpenROAD-flow-scripts/flow/platforms/nangate45/lib/NangateOpenCellLibrary_typical.lib
read_db /work/npu_pe_v3/out/results/nangate45/npu_pe/base/6_final.odb
read_sdc /work/npu_pe_v3/out/results/nangate45/npu_pe/base/6_final.sdc
read_spef /work/npu_pe_v3/out/results/nangate45/npu_pe/base/6_final.spef
read_vcd -scope tb_pe_power/dut /work/gl_v3.vcd
report_power
