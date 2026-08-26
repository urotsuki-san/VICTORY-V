# Changelog

## 0.4.0-alpha.0 — 2026-08-26

- Added the Tang 138K `1P1E + VV32` bring-up image.
- Kept P0 and E0 on the same `VV64-A0` ISA while giving them different Capability Directory and Victory Region budgets.
- Added a fixed VV32 -> P0 -> E0 release chain, three boot mailboxes, and three UART messages.
- Added a shared timebase, per-VV64 timer compares, software interrupt bits, and per-requester core information.
- Added the three-core self-checking simulation and kept the original two-core regression.
- Switched the Mega and Console Gowin projects to the three-core SoC.
- Added a machine-readable Tang 138K platform manifest.
- Fixed the no-MMU Linux and DOOM path around P0, E0, and the permanent VV32 control core.

## 0.3.0-alpha.0 — 2026-08-26

- Added a native 64-bit SystemVerilog core for the first `VV64-A0` FPGA subset.
- Kept the inherited VV32 primary opcode positions and added `XMEM` doubleword access.
- Added a protected 32-entry Capability Directory with generation-checked register references.
- Added VV64 Secret Tags, `VLOCK`, Victory Regions, basic CSRs, traps, and an interrupt input.
- Added a Tang 138K bring-up SoC with VV32-A0 and VV64-A0 in one image, separate RAM, shared UART, mailboxes, and status LEDs.
- Added generated boot ROMs, self-checking VV64 and dual-core simulations, and consistency checks.
- Added Gowin projects for Tang Mega and Tang Console 138K, device revisions B and C.
- Documented the exact boundary between the FPGA subset and the later Linux-capable architecture.

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
