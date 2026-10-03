# Edge-AI SoC — 28 nm, 8 TOPS INT8 (Auralis design)

Spec: 28 nm edge-AI SoC for INT8 CNN and Transformer workloads. 8 TOPS. INT8×INT8 and
INT16×INT8 → INT32. 8 MB SRAM with ECC. LPDDR4 at ≥ 25 GB/s. 4× RV64GC. NPU systolic array
with WS/OS dataflows. MIPI/PCIe/USB/Ethernet. < 3 W average. < 35 mm². 1 GHz. Watchdog, error
reporting, secure boot and accelerator isolation.

How it was made: each block was written, then checked with Verilator lint, Icarus simulation
and Yosys synthesis. The plugin's `semiconductor_validate` ran them. Laya alone gave each
version PASS or FIX, and blocks were iterated until Laya said PASS. Evidence came from the
Auralis knowledge base (TurboVec 2-bit + BM25 + Laya rerank). There was no web search. In the
later blocks, Laya also rated whether the evidence was good enough (SUFFICIENT/REFINE), and
retrieval was repeated when it was not. Every block has a design record in the knowledge base,
and every verdict is in the decision ledger.

## Block diagram

```
            OTP digest/min-version
                   │
 boot flash ──► secure_boot (SHA-256 RoT) ──cpu_rst_n──► 4× RV64GC cluster (CVA6, L1/L2, PLIC)  [IP]
                                                           │ master
   ┌───────────────────── interconnect (round-robin, decode, error resp) ─────────────────────┐
   │ masters: CPU, DMA(via IOPMP)                                                               │
   └──┬──────────┬────────────┬──────────────┬────────────┬───────────────┬──────────────┬─────┘
   SRAM 8MB   NPU core      registers:     LPDDR4 ctrl   peripherals     boot flash
   SECDED     (tiler +      NPU DMA IOPMP  +PHY [IP]     MIPI CSI-2,     (read-only
   (16 banks) R×C array +   WDT ERR PMU    25.6 GB/s     PCIe3, USB3,    after boot)
              requant)      SYS                           Ethernet [IP]
 dma2d ─► iopmp (isolation) ─► interconnect          err_agg ◄── ECC, IOPMP, DMA, WDT, boot, PMU, decode
 pmu: clock/power domains, retention, isolation, thermal throttle      watchdog: bark → bite → reset
```

## Blocks and verification

| Block | File | What it does | Checks | Laya |
|---|---|---|---|---|
| NPU PE | `npu_pe.sv` | INT8/INT16×INT8→INT32 MAC, WS and OS modes | 844/844 | PASS |
| Systolic array | `npu_array.sv` | R×C array with input skew and output de-skew; 64×64 = 8.19 TOPS | 384/384 | PASS (0.92) |
| ECC SRAM | `secded.sv`, `sram_ecc.sv` | SECDED(72,64), correct + scrub, double-error detect, fault injection | 1388/1388 | PASS (0.92) |
| DMA + isolation | `dma2d.sv`, `iopmp.sv` | 2-D strided DMA; 8-region IOPMP, default deny, lock, violation log | 240/240 | PASS (0.93) |
| Reliability | `watchdog.sv`, `err_agg.sv` | windowed keyed WDT bark→bite; first-fault latch aggregator; reset sync | 27/27 | PASS (0.94) |
| Secure boot | `sha256.sv`, `secure_boot.sv` | HW SHA-256, OTP digest, constant-time compare, anti-rollback, fail-closed | 61/61 | PASS (0.90) |
| NPU core | `npu_core.sv` | programmable tiled GEMM (OS), buffers, requant (round/zero-point/ReLU/sat) | 479/479 | PASS (0.94) |
| Power | `pmu.sv` (+`icg`) | per-domain clock/iso/retention/switch sequencing, timeouts, auto-idle, thermal throttle | 20 + per-cycle protocol checker | PASS (0.94) |
| **SoC top** | `soc_top.sv` | integration + interconnect + memory map | **118/118**, full-chip synth 121,370 cells | v1 FIX → v2 FIX → v3 FIX → **v4 PASS (0.88)** |

The SoC-level test covers these steps. Secure boot releases the CPUs. The test then exercises
SRAM, and runs a DMA from LPDDR4 into SRAM through the IOPMP. Operands are DMA'd into the NPU,
which runs a GEMM with INT8 requantization and raises an interrupt. Next come an isolation
violation (blocked, logged, with first-fault root cause), a decode error, and the peripheral
window. The watchdog then barks, bites and raises a fatal reset request. Finally, a tampered
boot image is rejected and the CPUs stay in reset.

Bugs that the loop found and fixed:
- The first-fault expectation in the SoC test was wrong. The latch had correctly kept the
  earlier decode error as the root cause.
- The `faults` bus was 17 bits wide, so the watchdog **bite was silently dropped** before the
  error aggregator. Verilator lint caught it; simulation had not.
- A Yosys-incompatible cast and a width warning.

## Memory map

| Base | Target |
|---|---|
| `0x0000_0000` | boot flash (secure boot only until `boot_ok`; then read-only) |
| `0x1000_0000` | on-chip SRAM, 8 MB, SECDED |
| `0x2000_0000` | NPU buffers (`+0x00_0000` ABUF, `+0x10_0000` WBUF, `+0x20_0000` CBUF) |
| `0x3000_0000` | registers: `0x0xxx` NPU, `0x1xxx` DMA, `0x2xxx` IOPMP, `0x3xxx` WDT, `0x4xxx` ERR, `0x5xxx` PMU, `0x6xxx` SYS |
| `0x4000_0000` | peripheral subsystem (MIPI CSI-2, PCIe Gen3, USB 3.0, Ethernet) |
| `0x8000_0000` | LPDDR4 |

Fault sources: 0 ECC corrected, 1 ECC uncorrectable (fatal), 2 IOPMP, 3 DMA error, 4 WDT bark,
5 boot fail, 6 power-domain error, 7 decode error, 15 WDT bite (fatal).

## Added in round 2: CPUs, memory interface, interface PHYs, physical design, analog

| Block | Files | Result | Laya |
|---|---|---|---|
| NPU PE v4: 3-stage pipeline + operand isolation | `rtl/npu_pe.sv` | 804 checks (+ array 384, NPU 479, SoC 118) | PASS 0.87 |
| 4 x CVA6 RV64GC Sv39 cluster | `cpu/cpu_cluster.sv`, `cpu/axi2sbus.sv`, `cpu/cv64a6_auralis_config_pkg.sv` | Verilator: 4 harts boot from cached LPDDR4, `amoadd.d` atomic across harts, racing byte stores kept: 7/7 | PASS 0.94 |
| LPDDR4 controller + PHY digital | `phy/lpddr4_ctrl.sv`, `phy/lpddr4_phy.sv`, `phy/lpddr4_dram_model.sv` | per-lane read-DQ training, 763/763, 0 timing violations | PASS |
| SerDes PCS: 8b/10b + link training, 64b/66b, 128b/130b | `phy/codec8b10b.sv` (generated, property-checked), `phy/pcs.sv` | 3,265/3,265 | PASS 0.87 |
| MIPI CSI-2 RX (4-lane D-PHY align, ECC, CRC) | `phy/mipi_csi2_rx.sv` | 10/10 | PASS 0.84 |
| Ethernet MAC | `phy/eth_mac.sv` | 94/94 | PASS 0.93 |
| PCIe data link layer (seq, LCRC, ACK/NAK, replay) | `phy/pcie_dll.sv` | clean and 0.5 % corrupted link: all TLPs in order, exactly once | PASS 0.90 |
| USB 3.0 link layer (HP CRC, LGOOD/LBAD/LCRD, retry, credits) | `phy/usb3_link.sv` | clean and lossy link: all HPs in order, once | PASS 0.91 |
| StrongARM comparator (receiver sampler), transistor level | `analog/strongarm.sp` (SKY130, ngspice) | 24/24 decisions tt/ss/ff, 0.5-50 mV, worst 338 ps < 500 ps at 1 GHz, 118-147 fJ | PASS 0.85 |
| **Full chip**: secure boot -> 4 CVA6 run the verified image from flash -> LPDDR4 (trained PHY) store/load -> CPU-programmed IOPMP + DMA LPDDR4->SRAM -> atomics | `rtl/soc_full.sv`, `tb/tb_soc_full.sv`, `cpu/sw/firmware.py` | **9/9** (Verilator), 0 DRAM timing violations | PASS 0.91 |

Bugs found by the loop in round 2 (all fixed): per-core atomics adapters lost AMO updates across
cores (one shared adapter after the core merge); byte stores from different cores raced in the
bridge's read-modify-write (bus lock); 32-bit MMIO registers 4 bytes apart were mis-addressed by the
64-bit bridge (MMIO byte-lane path); LPDDR4 back-to-back writes cut off the previous BL16 burst;
PCIe DLL dropped a TLP arriving while the previous one drained (delivery FIFO) and lost counter
updates with several writers per cycle; the EDA server leaked containers on timeout.

### Physical design (OpenROAD, open Nangate45 45 nm kit) and measured power

| PE version | Area | Worst slack at 1 GHz | Power (gate-level VCD, 50 % zero activations) |
|---|---|---|---|
| v2 pipelined | 2,906 um2 | -0.10 ns | 3.42 mW |
| v3 register enables | 3,129 um2 | -0.07 ns | 3.64 mW (+6 %) |
| **v4 operand isolation** | 3,052 um2 | **+0.02 ns (met)** | **3.20 mW (-6.4 %)** |

Method note: annotating an RTL VCD only reached the 119 ports (internal activity was guessed) and
gave wrong answers; the numbers above come from gate-level simulation of each routed netlist with
cell models generated from the Liberty file (`pnr/lib2v.py`), ~6,000 pins annotated.
Scaled to 28 nm: ~1,150 um2 and ~1.35 mW per PE -> 64 x 64 array ~4.7 mm2, ~5.5 W at 100 % load.
**The < 3 W average target therefore needs <= ~40 % average NPU utilisation** (PMU auto-idle /
throttle), or further reduction (clock-gate insertion, lower Vdd at 28 nm).

## Still behavioural / not done

- Analog front ends other than the sampler: TX drivers, CTLE/DFE, CDR, PLL/DLL, D-PHY LP/HS.
  Behavioural models only; no free 28 nm PDK for silicon-accurate design (SKY130 used as a proxy).
- PCIe transaction layer and configuration space, USB 3.0 protocol layer, 10G Ethernet XGMII adaptation.
- Full-chip physical design (only the PE was placed and routed).

## Integration IP (connected through ports, not generated)

| Function | Suggested free/open IP | Port in `soc_top` |
|---|---|---|
| 4× RV64GC, Linux, L1/L2, PLIC/CLINT | CVA6 (OpenHW) cluster | `cpu_*`, `irq[7:0]` |
| LPDDR4 controller + PHY (64-bit, 3200 MT/s = 25.6 GB/s) | foundry/vendor PHY + open controller | `ddr_*` |
| MIPI CSI-2, PCIe Gen3, USB 3.0, Ethernet | vendor PHYs + open controllers | `per_*` |
| SRAM macros, OTP, power switches, ring-oscillator temp sensor | foundry compilers / analog | inferred arrays, `otp_*`, `pwr_*`, `temp` |

## PPA estimate (28 nm, **estimate — no free 28 nm PDK, so no signed-off STA/area**)

- **Throughput:** 64×64 PEs × 2 ops × 1 GHz = **8.19 TOPS** INT8. ✅
- **Memory bandwidth:** LPDDR4-3200, x64 = **25.6 GB/s**. ✅ (≥ 25 GB/s)
- **Area (rough):**

  | Block | Estimate |
  |---|---|
  | 8 MB SRAM + 12.5 % ECC (75.5 Mb) | ~14–17 mm² |
  | NPU array (4096 PEs) | ~6–9 mm² |
  | 4× CVA6 + caches | ~4–5 mm² |
  | LPDDR4/PCIe/USB/MIPI/Ethernet PHYs | ~6–7 mm² |
  | Glue | ~1–2 mm² |
  | **Total** | **≈ 31–40 mm²** |

  So the 35 mm² limit is **at risk**. It needs high-density SRAM compilers and a compact PE.
- **Power:** at full load the NPU draws about 4.1 T MAC/s × ~0.5 pJ ≈ 2 W. Add CPUs (~0.5 W)
  and the DDR PHY (~0.4 W) for a peak of ~3 W. The < 3 W **average** is reachable with the PMU
  (auto-idle, clock gating, thermal throttle) at realistic duty cycles.
- **1 GHz timing risk:** the knowledge base (ITA paper) gives 500 MHz as a *conservative* 28 nm
  target. A 16×8 multiply plus a 32-bit accumulate in one cycle will need **one extra pipeline
  stage in `npu_pe`**. The systolic skew absorbs the added latency. This is not done yet.

## What is not done (honest)

- CPU cluster, LPDDR4 controller/PHY and interface PHYs are integration IP, not written here.
- Physical design: synthesis to a real library, STA at 1 GHz, place-and-route, power analysis.
  The next free step is OpenROAD on SKY130/GF180 as a proxy, scaled to 28 nm.
- PE pipelining for 1 GHz. AXI4 bridges if the CPU IP needs AXI. ECDSA verification of later
  boot stages, which the hash-anchored stage-1 software does.

## Reproduce

```bash
python validate.py rtl/<block files> tb/tb_<block>.sv      # through the auralis-semiconductor MCP server
./sim.sh tb_soc_top rtl/*.sv tb/tb_soc_top.sv               # full-chip simulation (auralis-eda image)
```
