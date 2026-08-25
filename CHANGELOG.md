# Changelog

## 0.2.0-alpha.0 — 2026-08-26

- Defined `VV32-A0` as the permanent source architecture of the VICTORY-V family.
- Added the native `VV64-A0` design contract without introducing another host ISA.
- Kept page translation optional and split Linux work into flat and paged profiles.
- Added the Capability Directory, tagged context, sealed control flow, capability-checked atomics, and interrupt-abort Victory Region design.
- Added a machine-readable family manifest, Python profile API, `vv profiles`, tests, and manifest checks.
- Added native Linux, FPGA, and primary-source research notes.
- Reworked repository prose while preserving the README layout and hero image.
- Fixed the cross-platform Python CI installation path.

## 0.1.0-alpha.0 — 2026-08-25

- Defined the executable `VV32-A0` instruction contract.
- Added the assembler, disassembler, binary format, and Python reference machine.
- Added capability bounds and permission checks, `VLOCK`, Secret Tags, and explicit declassification.
- Added bounded Victory Regions with forwarding, commit, rollback, errors, quotas, and budgets.
- Added a board-independent SystemVerilog core, self-checking testbench, formal harness, CI, examples, and the Tang Nano 20K handoff gate.
