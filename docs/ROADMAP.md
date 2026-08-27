# Roadmap

## A0 FPGA handoff

- [x] VV32 and VV64 executable/RTL baselines;
- [x] complete register, capability, and VV64 Directory rollback;
- [x] immediate Region preemption path;
- [x] direct `VTRY` entry for compact contracts;
- [x] one-shot `VPREP` / prepared `VTRY` / `VCANCEL` path;
- [x] store, instruction, register, capability, arena, and release admission;
- [x] merged write-set buffering and all-entry commit preflight;
- [x] Region device rejection and fixed-release secret contracts;
- [x] 32-bit Capability Directory and VRTU generations;
- [x] three-core `VV32 + P0 + E0` image with direct/prepared `VTRY` and rollback self-tests;
- [x] exact VRTU Python model and synthesizable RTL;
- [x] 4-entry P0 and 2-entry E0 integration;
- [x] Euclid removed from the default image and isolated as an experiment;
- [x] Mega/Console B/C Gowin projects synchronized;
- [x] model, RTL, documentation, and structural checks;
- [ ] Gowin utilization and warnings recorded;
- [ ] 50 MHz place-and-route;
- [ ] board UART/LED and contract-boundary evidence.

## No-MMU Linux

```text
privilege and traps
  -> tagged context
  -> timer and IPI
  -> atomics/fences
  -> standalone DDR3
  -> shared uncached memory
  -> compiler/lld
  -> CONFIG_MMU=n early console
  -> initramfs / BusyBox
  -> framebuffer / input
  -> doomgeneric
```

## Before a stable ISA

- keep the overloaded `VTRY` syntax stable: three operands select `VTRY.I`, two select `VTRY.C`;
- replace the packed A0 `rSpec` with a versioned, extensible descriptor only after the toolchain can consume it;
- define which contract fields are architectural and which remain profile capacity;
- keep direct `VTRY` available for small jobs.

## After measurement

- reduce VRTU comparator depth only if timing requires it;
- measure whether the last-range guards earn their area and switching cost;
- wire Monitor-owned descriptor derivation and lock into boot firmware;
- define the DDR/shared-memory no-fault publication domain;
- add transactional device queues only for devices that need contracted output;
- add paged `V39` only for a demonstrated workload need;
- replace structural formal checks with cycle-accurate observational equivalence between the executable model and RTL.

## Experiments

`experiments/euclid/` remains available through `make experiment-euclid`. It does not gate the processor or FPGA handoff.
