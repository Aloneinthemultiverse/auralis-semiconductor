# Edge-AI SoC — session log and lessons for the next AI

What was built, the decisions made, the mistakes and how each was caught. It is written for the
next agent that picks up this project. The per-block evidence is in the Auralis knowledge base
("Edge-AI SoC design record: …"), and every PASS/FIX verdict is in the decision ledger (`decisions_recent`).

## Workflow the user wants (do not deviate)
- References come from the Auralis RAG (TurboVec 2-bit + BM25 + Laya rerank), not from web search.
- Laya decides every control step:
  - PASS/FIX on each design version (iterate until PASS);
  - SUFFICIENT/REFINE on retrieved evidence.
- Every block gets written to the knowledge base as a design record: sources, results, verdict.
- Use free tools only. Never fake results; state limits plainly.
- Don't stop to ask; finish the task. Keep tokens low: lean RAG, short updates.

## What exists (designs/edge_ai_soc)
- **RTL:** NPU (PE v4 / array / tiler + requant), ECC SRAM, DMA + IOPMP, secure boot (SHA-256),
  watchdog, error aggregator, PMU, `soc_top`, and `soc_full` (+ 4× CVA6 + LPDDR4).
- **phy/:**
  - LPDDR4 controller, PHY with training, and DRAM model;
  - 8b/10b, 64b/66b and 128b/130b PCS;
  - CSI-2 RX, Ethernet MAC, PCIe DLL and USB3 link layer.
- **analog/:** StrongARM sampler (SKY130, ngspice).
- **pnr/:** OpenROAD Nangate45 runs and gate-level power.
- **Full chip:** 9/9 in Verilator.

## Lessons (each one cost at least a debug cycle)

### Verification
1. **Lint catches what simulation misses.**
   - A 17-bit `faults` bus silently dropped the watchdog bite, and the full-chip sim still passed.
   - Always run Verilator `-Wall`, and treat WIDTH warnings as bugs.
2. **Per-port atomics adapters are wrong.**
   - `axi_riscv_atomics` must sit after the core merge (one shared instance). Otherwise AMOs from
     different harts lose updates.
   - A read-modify-write for byte stores also needs a bus lock across the read and the write.
3. **The bus word size versus 32-bit MMIO.**
   - A 64-bit bridge that aligns every address to 8 bytes mis-addresses registers placed 4 bytes apart.
   - MMIO windows need exact addresses and byte-lane shifting.
4. **Burst occupancy.**
   - Acknowledge a DRAM write only after the full BL16 burst (tCCD). Otherwise back-to-back
     writes cut off late beats.
5. **Several writers per cycle.**
   - With multiple nonblocking assignments to a counter in one cycle, the last one wins and
     counts are lost.
   - Compute per-cycle deltas in blocking temporaries and assign once.
6. **Receivers must not silently drop good packets.**
   - Give the receiver buffering (a FIFO), or the link only recovers by timeout.
   - Size the replay timeout from the buffer depth plus the ACK round trip.
7. **Test the expectations, not just the design.**
   - Twice the "failure" was the testbench: the first-fault latch was correct; the TB latency
     alignment was wrong.
   - Read the failure pattern before changing RTL.

### Tools (free stack quirks)
8. **Icarus 12:** no `break`, no queue arguments, no unpacked-array localparams, no compound
   assignment to array elements, no part-select `force`. Failures are often *silent*
   (exit code 1 or 2 with no message). Bisect by stubbing sections.
9. **Yosys 0.33:** no `return` in functions (assign to the function name), no multi-dimensional
   packed nets, and size casts of expressions sometimes fail.
10. **Validator (semiconductor MCP):**
    - The simulation top is the **first module** in the `tb_*.sv` file.
    - Only `.sv` content reaches it, so embed test vectors in the testbench.
    - Timeout is now 600 s. It used to leak containers on timeout: fixed with a named container
      plus `docker kill`.
11. **Verilator `--timing`:**
    - A TB loop that calls a function in its `while` condition never advanced time.
    - Use clocked sampling flags.
    - Debug hangs with gdb `bt`: the frame names show which process spins.
    - Output to a file is buffered and lost on timeout; use `stdbuf -oL`.
12. **Verilator needs g++.** The image is `auralis-eda-cxx`. A CVA6 build takes about 10 minutes.

### Power and physical design
13. **Annotating an RTL VCD only reaches the ports.** Here 119 pins were annotated and internal
    activity was guessed, which gave wrong conclusions.
    - Use gate-level simulation of the routed netlist, with cell models generated from the
      Liberty file (`pnr/lib2v.py`).
14. **Measure before claiming savings.**
    - Register-enable "gating" cost +6%: the enables became muxes and the multiplier still switched.
    - Operand isolation before the multiplier saved 6.4%.
15. **28 nm figures are scaled from Nangate45 (45 nm) and SKY130.** Say so every time.

### RAG / Laya
16. **Laya is calibrated for short questions with titles-only state.** Adding passage text, or a
    coverage line, to its state flips correct answers.
17. **Long multi-term queries fool both the reranker and the sufficiency rating.**
    - Irrelevant sources were rated SUFFICIENT and scored 1.00.
    - Guard: SUFFICIENT needs Laya's yes **and** ≥ 50% key-term coverage in the passages.
18. **Do not let a slow LLM step share Ollama with embeddings.** An abandoned rewrite kept
    generating and stalled retrieval. Query expansion from the evidence terms is used instead.
19. **Your own design records enter the corpus** and will match later queries (that's fine, but
    keep it in mind when testing retrieval).

## Open items (as of 2026-10-03)
- **Power:** < 3 W average holds only at ≤ ~40% average NPU load (array ~5.5 W at 100%). Next
  steps are ICG insertion and a lower Vdd.
- **Analog:** TX driver, CTLE/DFE, CDR, PLL/DLL and D-PHY LP/HS are behavioural only.
- **Protocol layers:** PCIe transaction layer and configuration space, USB 3.0 protocol layer,
  10G XGMII adaptation.
- **Physical design:** full-chip place-and-route. Only the PE has been placed and routed.
- **Commits:** both repos are committed locally and not pushed.
