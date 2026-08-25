# Changelog

All notable project changes are documented here. The project follows semantic-versioning intent, but A0 architecture details may still change incompatibly before `1.0.0`.

## 0.1.0-alpha.0 — 2026-08-25

- Defined the executable `VV32-A0` 32-bit ISA contract.
- Added the assembler, disassembler, binary format, and Python reference machine.
- Added capability bounds/permission enforcement and irreversible `VLOCK`.
- Added secret-tag propagation, prohibited secret branches/addresses, and authorized declassification.
- Added bounded Victory Regions with store forwarding, commit, rollback, error reporting, quotas, and instruction budgets.
- Added a board-independent SystemVerilog core, self-checking testbench, and initial formal harness.
- Added CI, examples, architecture documentation, threat model, provisional ABI, and Tang Nano 20K handoff gate.
