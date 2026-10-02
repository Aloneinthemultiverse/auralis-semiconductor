# Auralis Semiconductor — AI Semiconductor Engineering Scientist

The semiconductor domain for [Auralis](https://github.com/Aloneinthemultiverse/auralis):
**purpose → research → architecture → RTL → verify → measure → refine**, with the Laya
decision model controlling the loop and every decision recorded.

Auralis core stays domain-neutral. This repo plugs semiconductor design into it as an
**MCP domain server**: Auralis discovers any connected server exposing a
`<domain>_guidance` + `<domain>_validate` tool pair and lets Laya route objectives to it.

## What is here

| Path | What |
|---|---|
| `server/` | Java 21 / Spring Boot 4 MCP server on `:8090/mcp` |
| `eda/` | Docker image `auralis-eda`: Verilator, Icarus Verilog, Yosys (all free/open) |
| `knowledge/library.json` | Manifest of legally free semiconductor sources ingested into Auralis RAG |
| `plugin/` | Claude Code plugin: `chip-design` skill, `/auralis-semiconductor:chip` |

### MCP tools

| Tool | Does |
|---|---|
| `semiconductor_guidance` | Design rules for synthesizable SystemVerilog + self-checking testbenches |
| `semiconductor_validate` | Lint (Verilator -Wall) → simulate every `tb_*.sv` (Icarus) → synthesize top (Yosys); `SUMMARY … OVERALL PASS/FAIL` |
| `rtl_lint`, `rtl_simulate`, `rtl_synthesize` | The individual EDA steps |

### The loop (in Auralis core, driven for this domain)

```
spec ─▶ requirements ─▶ Laya: spec complete? ─▶ Laya: domain = semiconductor
     ─▶ alternatives ─▶ Laya: select ─▶ RTL + testbench (LLM, Laya-selected tools)
     ─▶ semiconductor_validate (lint · sim · synth) ─▶ LLM review
     ─▶ Laya verdict: PASS | FIX | RESEARCH (runs research, feeds back) | ASK_USER
     ─▶ version tree (what-if branches) ─▶ decision ledger
```

## Knowledge library

`knowledge/library.json` lists only open or freely distributed sources (RISC-V ISA manual,
Microprocessor Design, Computer Organization and Design Fundamentals, Lessons in Electric
Circuits — Digital, Free Range VHDL, Verilator and Yosys manuals) with their licenses.
Import (downloads, ingests, builds the `semiconductor-library` graph):

```bash
curl -X POST localhost:8080/api/graph/import/library -H 'content-type: application/json' \
  -d '{"manifest":"<abs path>/knowledge/library.json"}'
```

Paid standard texts are listed under `wanted`; add copies you own with `knowledge_add_file`.

## Run

```bash
docker build -t auralis-eda eda
cd server && ./mvnw spring-boot:run          # :8090
```

Or just run `scripts/start-auralis.sh` from the Auralis repo (sibling checkout): it builds
the image and starts this server along with the rest of the stack.

Claude Code: `/plugin marketplace add <this repo>` then `/plugin install auralis-semiconductor@auralis-semiconductor`
(install the `auralis` plugin too — design and research tools live in the core).

## Limits

- Yosys generic synthesis gives cell counts (area proxy), not timing or power; OpenROAD
  with a real PDK is the next step.
- Verification is as good as the generated testbench.
- The default local LLM is small (qwen3:4b); complex blocks need several FIX iterations.
