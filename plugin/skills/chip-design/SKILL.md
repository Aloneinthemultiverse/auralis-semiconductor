---
name: chip-design
description: Design digital hardware with Auralis — from a chip purpose or specification to research-backed architecture, synthesizable SystemVerilog RTL, automated verification (Verilator lint, Icarus simulation, Yosys synthesis/area) and a Laya-controlled refine loop with what-if branches. Use for any request to design, generate, verify or optimise RTL, a processor, accelerator, controller, interface or other digital block.
---

# Chip design with Auralis

Auralis is a closed-loop engineering scientist: **purpose → research → architecture → RTL →
verify → measure → refine**, with the fast decision model Laya making the control decisions
(spec complete? which architecture? which tools? pass/fix/research/ask?). Every decision is
logged in a ledger you can show the user.

Requires both plugins' servers running: Auralis core (`auralis` MCP: research, design,
knowledge, decisions) and this domain server (`auralis-semiconductor` MCP: EDA tools).
Check with `auralis_status` first; if anything is down, tell the user to run
`scripts/start-auralis.sh` in the Auralis repo (it also starts the semiconductor server)
instead of improvising a design from memory.

## Workflow

1. **Requirements first.** Restate the purpose as requirements: function, interfaces/ports,
   clock target, throughput/latency, area and power budget, reset scheme, technology
   assumptions, verification expectations. If something that changes the architecture is
   missing, ask once; otherwise proceed and state assumptions explicitly.
2. **Ground it in knowledge.** `knowledge_search` the semiconductor library (RISC-V ISA
   manual, microprocessor design, digital design, HDL, Verilator and Yosys manuals) for the
   core concepts. `graph_browse` with namespace `semiconductor-library` shows what is
   available. Cite what you use.
3. **Research gaps** (optional, for non-trivial blocks): `research_start` with the objective;
   use `deepResearch: LOCAL` only if the library lacks the topic. Poll `research_status`.
4. **Design**: `design_start` with the full objective (include the requirements and
   assumptions) and the `researchSessionId` if you ran research. Auralis extracts
   requirements, proposes alternatives, Laya picks one, the RTL + self-checking testbench
   are generated and **automatically linted, simulated and synthesized** each iteration.
   Poll `design_status` every 1-2 minutes; report the trace briefly.
5. **Report** when the status is VERIFIED / EXHAUSTED / NEEDS_INPUT / FAILED:
   - the chosen architecture and why (alternatives with Laya scores, the decision ledger);
   - the verification SUMMARY line (lint, simulation pass count, synthesis, cell count);
   - the RTL files (`design_status` with `includeFiles: true`) — save them into the user's
     workspace if they want them;
   - what is unverified (no timing/power yet: Yosys cell count is only an area proxy).
6. **What-if**: for "what if we add a cache / halve the area / deepen the pipeline", use
   `design_branch` from the version to compare, then compare verdicts and cell counts.

## Quick checks without a full run

For RTL the user already has, call the EDA tools directly: `rtl_lint`, `rtl_simulate`
(with a self-checking testbench), `rtl_synthesize`, or `semiconductor_validate` with all
files as a JSON object.

## Honesty rules

- A design is only "verified" to the extent of its testbench; say what the tests cover.
- Laya scores are control signals from a small model, not confidence in correctness.
- The local main LLM is small (4B); for complex blocks expect FIX iterations, and review
  the RTL yourself before presenting it as finished.
