# Changelog

## 0.7.0-alpha.0 — 2026-08-27

- Extended `VTRY` with a one-shot prepared path using `VPREP`, `VTRY cToken, fail`, and `VCANCEL`.
- Kept direct `VTRY fail, stores, budget` as the compact inline form.
- Added explicit store, instruction, register-write, derived-capability, arena, and release-cycle limits.
- Added fixed architectural release for contracts marked secret.
- Merged repeated stores to the same aligned granule before quota accounting.
- Added all-entry commit preflight through the normal protection path before publication.
- Rejected Region access to VRTU `DEVICE` ranges and made post-publication faults fatal `COMMIT_PROTOCOL` errors.
- Expanded VV64 Capability Directory and VRTU generations to 32 bits and rejected wrap.
- Added VV64 Directory and allocator rollback plus contracted capability derivation.
- Wired logical access size, privilege, probe, and device state through the profiled VRTU path.
- Added model, assembler, RTL, structural, and consistency checks for the prepared contract path.
- Added Tang 138K first-light ROM checks for direct `VTRY`, prepared `VTRY`, rollback, and VV64 device rejection.
- Removed the separate prepared-entry mnemonic; `VTRY` now selects inline or prepared encoding by operand count.
- Reconciled the active architecture, FPGA handoff, threat model, roadmap, RTL notes, and archived Euclid documents.

## 0.6.0-alpha.0 — 2026-08-27

- Removed Euclid from both board tops and all four Tang 138K Gowin projects.
- Moved the Euclid model, RTL, testbench, and notes to `experiments/euclid/`.
- Added the exact dual-path Victory Range Translation Unit.
- Added four P0 and two E0 VRTU entries with a locked no-MMU reset map.
- Added generation-checked guarded reuse without a TLB refill or page walker.
- Added causes 20–22 for VRTU miss, permission, and overlap conflict.
- Routed VV64 instruction, data, and commit traffic through VRTU.
- Added Python and self-checking RTL VRTU tests.

## 0.5.0-alpha.0 — 2026-08-26

- Added the Euclid Plane executable model for exact early decisions.
- Added `Euclid-A0` RTL: four candidates, up to eight signed 8-bit coordinates, exact squared-distance selection, and one guarded Atlas entry.
- Added a standalone self-checking Euclid testbench.
- Put Euclid into all Tang Mega/Console 138K Gowin projects through `vv_cluster_euclid_bringup`.
- Added a board self-test: VV32 drives the first proof, then P0 and E0 milestones trigger guarded Atlas reuse checks.
- Kept the CPU count at three. Euclid was an attached decision engine, not another CPU.
- Kept the general CPU-visible Euclid gateway out of A0 until its capability and timing rules could be defined.
- Added `tools/check_docs_sync.py` to catch stale architecture prose and accidental README layout drift.

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
- Documented the boundary between the FPGA subset and the later Linux-capable architecture.

## 0.2.0-alpha.0 — 2026-08-26

- Defined `VV32-A0` as the permanent source architecture of the VICTORY-V family.
- Added the native `VV64-A0` design contract without introducing another host ISA.
- Kept page translation optional and split Linux work into flat and paged profiles.
- Added the Capability Directory, tagged context design, sealed control-flow notes, capability-checked atomics design, and interrupt-abort Victory Region design.
- Added a machine-readable family manifest, Python profile API, `vv profiles`, tests, and manifest checks.
- Added native Linux, FPGA, and primary-source research notes.
- Fixed the cross-platform Python CI installation path.

## 0.1.0-alpha.0 — 2026-08-25

- Defined the executable `VV32-A0` instruction contract.
- Added the assembler, disassembler, binary format, and Python reference machine.
- Added capability bounds and permission checks, `VLOCK`, Secret Tags, and explicit declassification.
- Added bounded Victory Regions with forwarding, commit, rollback, errors, quotas, and budgets.
- Added a board-independent SystemVerilog core, self-checking testbench, formal harness, CI, examples, and the Tang Nano 20K handoff gate.
