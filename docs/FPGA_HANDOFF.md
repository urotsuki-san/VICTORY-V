# Tang Nano 20K FPGA Handoff

## Objective

The first hardware target is one **Tang Nano 20K** board. This document defines the boundary between the board-independent A0 project and the board-specific implementation.

No second FPGA board is required for the first milestone.

## Pre-FPGA gate

Board work begins only after all blocking items pass on the exact main-branch commit intended for hardware:

- [x] fixed-width instruction encoding documented;
- [x] machine-readable opcode/CSR/cause manifest;
- [x] assembler and binary image generation;
- [x] executable reference model;
- [x] capability, secret-flow, commit, rollback, quota, and budget tests;
- [x] board-independent SystemVerilog core;
- [x] self-checking RTL smoke test for capability access, commit, rollback, and `VLOCK`;
- [x] CI definition for Windows, Linux, macOS model tests and Linux RTL simulation;
- [ ] CI is green on the public repository commit;
- [ ] all RTL warnings are reviewed rather than suppressed without explanation;
- [ ] Python and RTL traces are differentially compared for a generated instruction corpus;
- [ ] formal harness passes with a documented tool version;
- [ ] capability context-save strategy is either implemented or explicitly excluded from the first bare-metal bitstream.

The unchecked items are the remaining pre-hardware work. A green smoke test is necessary but not sufficient.

## First SoC scope

```text
Tang Nano 20K
├── VV32-A0 core
├── on-chip instruction RAM
├── on-chip capability-checked data RAM
├── boot/reset controller
├── UART transmit and receive
├── machine timer
├── external IRQ aggregation
└── minimal debug/status registers
```

The first bitstream excludes:

- external SDRAM;
- cache;
- MMU;
- Linux;
- HDMI;
- dynamic branch prediction;
- speculative execution;
- multicore;
- FreeRTOS until timer/interrupt/context behavior is stable.

## Proposed first memory organization

A0 currently uses separate instruction and data buses. The initial SoC can therefore use overlapping zero-based address spaces without ambiguity:

| Bus | Address | Size | Purpose |
|---|---:|---:|---|
| instruction | `0x0000_0000` | 32–64 KiB | boot image / program ROM or RAM |
| data | `0x0000_0000` | 32–64 KiB | deterministic on-chip working memory |

MMIO is deliberately deferred until its interaction with Victory Regions is specified. The first UART milestone may use a dedicated core-side debug port rather than pretending irreversible device writes are transactional memory.

## Tool flow

The intended open flow is:

```text
SystemVerilog
  → Yosys
  → nextpnr-himbaechel
  → Gowin packer / Apicula-compatible flow
  → openFPGALoader
  → Tang Nano 20K
```

A Gowin vendor-tool build should be retained as a cross-check before any correctness claim depends on one synthesis flow.

## First observable milestones

1. clock/reset and instruction fetch;
2. `HALT` smoke image;
3. UART text: `VICTORY-V IS ALIVE`;
4. ALU conformance image;
5. capability bounds failure image;
6. Victory commit/rollback image;
7. timer interrupt and bounded-region deferral image;
8. reference-model/FPGA trace comparison.

The first board release should publish the exact source commit, tool versions, constraints, utilization, maximum clock, bitstream hash, and UART transcript.
