# Roadmap

## Phase 0 — Architecture seed

**Status: complete for A0**

- define the fixed 32-bit encoding;
- define register metadata, capability permissions, secret tags, traps, and CSRs;
- redefine `VIC` as Victory Integrity Commit;
- publish an explicit threat model and non-goals.

## Phase 1 — Executable contract

**Status: implemented, validation continuing**

- dependency-free assembler and disassembler;
- deterministic Python reference machine;
- runnable commit, rollback, capability-fault, and secret-flow examples;
- machine-readable ISA manifest and drift checker;
- cross-platform test workflow.

## Phase 2 — Pre-FPGA RTL

**Status: prototype present; gate not yet closed**

- multi-cycle in-order SystemVerilog core;
- capability metadata and secret-tag register state;
- bounded store buffer and multi-cycle `VIC` commit;
- self-checking Icarus testbench;
- initial formal assertions.

Remaining work:

- generated differential model/RTL testing;
- close simulator warnings and model/RTL edge-case discrepancies;
- run the formal harness in CI or publish reproducible local results;
- decide capability save/restore format;
- freeze the exact A0 hardware subset.

## Phase 3 — Tang Nano 20K

**Status: not started**

- board clock/reset and constraints;
- instruction and data BSRAM wrappers;
- UART and timer;
- reproducible OSS and vendor synthesis flows;
- utilization, timing, and bitstream provenance;
- hardware conformance transcript.

## Phase 4 — Software platform

**Status: planned**

- minimal C compiler path or LLVM backend;
- C runtime and linker script;
- capability-aware context format;
- FreeRTOS port;
- later Zephyr evaluation.

## Phase 5 — Evidence

**Status: planned**

- generated conformance corpus;
- model/RTL/FPGA differential traces;
- resource and performance comparison against appropriately scoped small cores;
- fault-injection and negative tests;
- independent review;
- stable profile only after evidence supports it.
