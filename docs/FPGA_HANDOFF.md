# FPGA Targets and Handoff Gates

VICTORY-V has two hardware tracks. They share architectural tests but do not share one oversized first core.

## VV32-A0 — Tang Nano 20K

### Pre-hardware gate

- [x] fixed instruction encoding and machine-readable manifest;
- [x] assembler and binary image generation;
- [x] executable Python model;
- [x] capability, secret-flow, commit, rollback, quota, and budget tests;
- [x] board-independent SystemVerilog core;
- [x] self-checking RTL smoke test;
- [x] public CI definition;
- [ ] public CI is green on the exact hardware commit;
- [ ] RTL warnings are reviewed;
- [ ] generated Python/RTL differential traces pass;
- [ ] formal checks pass with pinned tool versions;
- [ ] capability context switching is implemented or explicitly excluded from the first bitstream.

### First SoC

```text
Tang Nano 20K
├── VV32-A0
├── instruction BSRAM
├── capability-checked data BSRAM
├── reset controller
├── UART
├── timer
└── interrupt input
```

External SDRAM, MMU, caches, HDMI, and Linux stay out of the first VV32 bitstream.

## VV64-A0 — Tang Console 138K

The 138K target uses a native VICTORY-V core. Board frameworks may supply clock, reset, DDR, UART, SD, and interconnect support; they do not supply a substitute CPU.

### Pre-hardware gate

- [ ] base and extension encoding frozen for the first prototype;
- [ ] executable 64-bit model and assembler;
- [ ] Capability Directory and tagged context tested;
- [ ] privilege, traps, timer, interrupts, atomics, and fences modeled;
- [ ] self-checking RTL core simulation;
- [ ] generated model/RTL differential corpus;
- [ ] physical-mode boot ROM and linker map;
- [ ] board clock/reset and UART wrapper;
- [ ] DDR3 controller tested independently before cache enable.

### Bring-up order

```text
on-chip RAM + UART
  -> tagged context switch
  -> timer and interrupts
  -> generation and sealed-call tests
  -> Victory Region and VTRYA tests
  -> DDR3 memory test
  -> no-MMU Linux early console
  -> FDPIC or FLAT userspace
  -> V39 MMU
  -> paged Linux
```

Starting with DDR3, caches, an MMU, and Linux in one bitstream would make failures needlessly hard to locate.

## Publication rule

A board release should include source and tool revisions, constraints, achieved clock, resource use, bitstream hash, UART transcript, conformance results, and known warnings. Synthesis alone is not enough; the same tests must agree in the model, RTL, and hardware.
