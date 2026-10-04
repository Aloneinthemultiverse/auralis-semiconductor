# Edge-AI SoC IP — foundry handoff package

**For:** a chip company integrating this RTL in its own process (TSMC / Samsung / GF / SCL) with its own
sign-off tools.

**What's in it:** synthesizable SystemVerilog, self-checking testbenches, assertions, SDC constraints,
memory macro hooks and verification evidence. It is **not** silicon-proven. Physical design was done
only on open PDKs (Nangate45, SKY130) as a proxy.

## 1. Deliverables

| Path | Content |
|---|---|
| `rtl/` | SoC RTL: `soc_full` (top), `soc_top`, NPU (`npu_pe`, `npu_array`, `npu_core`), `sram_ecc` + `secded`, `dma2d`, `iopmp`, `secure_boot` + `sha256`, `watchdog`, `err_agg`, `pmu`, `ram_1r1w` |
| `cpu/` | 4× CVA6 cluster integration (`cpu_cluster`, `axi2sbus`, CVA6 config). CVA6 itself is third-party (OpenHW, Solderpad 0.51) |
| `phy/` | LPDDR4 controller + PHY digital, SerDes PCS (8b/10b, 64b/66b, 128b/130b), CSI-2 RX, Ethernet MAC, PCIe DLL, USB3 link layer |
| `tb/`, `phy/tb_*.sv`, `cpu/tb_*.sv` | Self-checking testbenches (print `ALL TESTS PASSED`) |
| `assertions/soc_sva.sv` | 8 bound SVA protocol/safety properties (mutation-tested) |
| `constraints/*.sdc` | Timing constraints: 1 GHz core clock, IO budgets, false/multicycle paths |
| `pnr/`, `analog/` | Open-PDK proxy results (OpenROAD Nangate45/SKY130, ngspice SKY130) |
| `README.md`, `LESSONS.md` | Architecture, results, design log |

## 2. Clocks, resets, conventions
- **Single core clock `clk`, 1 GHz target.** Every flop is rising-edge.
- **Reset:** `por_n` is asynchronous and synchronised by `rst_sync` (assert async, release sync).
  Internal resets are synchronous active-low `rst_n`.
- **Clock gating:** PMU per-domain enables (`dom_clk_en`) are inferred enables. Map them to your
  library ICG, and replace the behavioural `icg` cell with the library cell.
- **No latches** (except the reference `icg` model), no `initial` in RTL, no simulator-only
  constructs in RTL. Verilator `-Wall` lint is clean per block.

## 3. Memories → foundry macros
Every RAM goes through `rtl/ram_1r1w.sv` (one read port, one write port, 1-cycle read).

| Instance | Width × depth (production) | Notes |
|---|---|---|
| `sram_ecc.u_mem` | 72 × 64K per bank, 16 banks = 8 MB + ECC | SECDED; scrub writes share the write port |
| `npu_core.u_abuf` | (R×16) × depth | activation buffer, R = 64 in production |
| `npu_core.u_wbuf` | (C×8) × depth | weight buffer |
| `npu_core.u_cbuf` | (C×32) × depth | output buffer |

**To use your macros:** compile `+define+AURALIS_FOUNDRY_RAM`, then provide
`foundry_ram_1r1w #(W, D)` wrapping your SRAM-compiler output (two-port RF or SRAM, plus BIST and
redundancy as your methodology requires).

## 4. Interfaces to integrate (not in this package)

| Port group in `soc_full` | Expected IP |
|---|---|
| `d_*` (LPDDR4 command/beat level) | LPDDR4 PHY hard macro (analog IO, DLL, ZQ). The digital PHY logic here does the training state machine and the DFI side |
| `fl_*` | QSPI/flash controller |
| `per_*` | Peripheral subsystem: PCIe/USB3/Ethernet/MIPI **analog PMAs** + the PCS/link layers in `phy/` |
| `pwr_en` / `pwr_ack`, `iso_en`, `ret_save` | Power switches, isolation cells and retention flops per UPF (write the UPF from `pmu.sv` domains) |
| `otp_*` | OTP/eFuse macro |
| `temp` | On-die temperature sensor |

## 5. Verification evidence (all reproducible)

| Block | Test | Result |
|---|---|---|
| NPU PE / array / core | `tb_npu_pe`, `tb_npu_array`, `tb_npu_core` | 804 / 384 / 479 checks pass |
| ECC SRAM | `tb_sram_ecc` | 1388 pass (all single-bit corrected, 300 double-bit detected) |
| DMA + IOPMP | `tb_dma2d` | 240 pass |
| Secure boot | `tb_secure_boot` | 61 pass (FIPS SHA-256 KAT, tamper, rollback) |
| Watchdog / errors | `tb_safety` | 27 pass |
| PMU | `tb_pmu` | 20 + per-cycle protocol checker |
| SoC top | `tb_soc_top` (+ SVA) | 118 pass, 0 assertion failures; assertions fire on injected bugs |
| CPU cluster (4× CVA6) | `cpu/tb_cpu_cluster` (Verilator) | 7/7: boot, AMOs across harts, byte stores |
| LPDDR4 ctrl + PHY | `tb_lpddr4` | 763 pass, 0 DRAM timing violations, 8 lanes trained |
| PCS | `tb_pcs` | 3265 pass |
| CSI-2 / Ethernet / PCIe DLL / USB3 link | `tb_csi2`, `tb_eth`, `tb_pcie_dll`, `tb_usb3` | all pass, incl. lossy-link recovery |
| **Full chip** | `tb_soc_full` (Verilator) | **9/9**: secure boot → 4 CPUs run firmware → LPDDR4 → DMA → atomics |

## 6. Porting to a foundry node (customer steps)
1. **Synthesis:** synthesise `soc_full` with your libraries and `constraints/soc_full.sdc`. Add the
   PDK uncertainty and derates. Expect the critical paths in the NPU requant multiply and the PE
   multiply (both are pipelined).
2. **Memories:** map `ram_1r1w` to compiled macros (section 3).
3. **Power intent:** write UPF from the PMU domains (NPU, CPU0-3, DMA, PERIPH).
4. **Hard macros:** integrate the PHY/PMA hard macros on the port groups in section 4.
5. **Sign-off:** run your commercial lint/CDC/formal on the RTL (single clock: CDC only at the PHY
   boundaries), then gate-level simulation, STA, power, DFT insertion (scan, MBIST).
6. **Re-run the testbenches on your simulator.** They are plain SystemVerilog plus SVA.

## 7. Known limitations (state these to the customer)
- **Proxy only:** 28 nm PPA comes from Nangate45 / SKY130 runs, not foundry sign-off.
- **Power:** < 3 W average needs ≤ ~40 % average NPU utilisation.
- **No DFT:** no scan or MBIST yet, and no CDC structures beyond the PHY boundary.
- **Single outstanding:** one transaction at a time on the internal SoC bus (not full AXI). Bandwidth
  to LPDDR4 is limited by it; a burst-capable AXI fabric is the upgrade path.
- **Not included:** PCIe transaction layer, USB3 protocol layer, 10G XGMII adaptation.
