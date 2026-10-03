# npu_pe — NPU systolic-array processing element

Designed by Claude via the Auralis plugin; verified with Auralis' semiconductor EDA
server; accepted by Laya (verdict PASS, 0.76).

| Check | Result |
|---|---|
| Verilator lint (-Wall) | clean |
| Icarus simulation (tb_npu_pe.sv) | 844/844 checks pass |
| Yosys generic synthesis | 1,444 cells, 96 flip-flops |

Spec coverage: INT8xINT8->INT32 and INT16xINT8->INT32 MAC with INT32 accumulation;
weight-stationary and output-stationary modes; systolic pass-through (activations
east, weights south); enable/hold.
