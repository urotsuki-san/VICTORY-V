# FPGA Targets and Handoff Gates

VICTORY-V has two architecture tracks and one Tang 138K cluster image.

The 138K image is a bring-up fixture. Three cores in one bitstream do not yet mean shared-memory SMP Linux.

## VV32-A0 — Tang Nano 20K

### Pre-hardware gate

- [x] fixed instruction encoding and machine-readable manifest;
- [x] assembler and binary image generation;
- [x] executable Python model;
- [x] capability, secret-flow, commit, rollback, quota, and budget tests;
- [x] board-independent SystemVerilog core;
- [x] self-checking RTL smoke test;
- [x] public CI definition;
- [ ] RTL warnings reviewed with the selected Gowin version;
- [ ] generated Python/RTL differential traces pass;
- [ ] formal checks pass with pinned tool versions;
- [ ] Tang Nano 20K clock, reset, RAM, UART, and constraints are committed.

VV32 is complete when it is a small reproducible FPGA CPU and a useful control core. Starting VV64 does not close this track.

## Tang 138K — 1P1E + VV32

The current image contains:

```text
VV32-A0 control core
VV64-A0/P0
VV64-A0/E0
```

P0 and E0 run the same ISA. P0 currently has a larger Capability Directory and Victory Region buffer. E0 has the smaller budget. Both still use the same execution engine.

### Pre-hardware gate

- [x] inherited VV32 opcode positions fixed for the VV64 prototype;
- [x] 64-bit integer/control and doubleword memory RTL;
- [x] protected Capability Directory with generation checks;
- [x] Secret Tags, `VLOCK`, and Victory Regions in RTL;
- [x] P0/E0 profile wrapper;
- [x] VV32 -> P0 -> E0 boot chain;
- [x] three private RAMs, shared UART, mailboxes, timebase, timer compare, and IPI bits;
- [x] self-checking VV64 and three-core simulations;
- [x] board clock/reset, UART, LED, and constraints for Mega and Console 138K;
- [x] machine-readable platform manifest;
- [ ] Gowin synthesis warnings reviewed;
- [ ] plain cluster stays within the resource gate;
- [ ] place-and-route passes the 50 MHz constraint;
- [ ] all three UART lines and status LEDs confirmed on hardware;
- [ ] generated model/RTL differential corpus;
- [ ] tagged context save and restore;
- [ ] Monitor/Supervisor/User privilege;
- [ ] atomics and fences;
- [ ] DDR3 controller tested independently.

### Current image

```text
VV32 ROM -> VV32 core -> private 64 KiB RAM --+
P0 ROM   -> P0 core   -> private 64 KiB RAM --+-> UART / control MMIO
E0 ROM   -> E0 core   -> private 64 KiB RAM --+
```

Expected output:

```text
VV32-A0 ready
VV64-P0 ready
VV64-E0 ready
```

See [`FPGA_138K_BRINGUP.md`](FPGA_138K_BRINGUP.md) for projects, pins, MMIO, and the first board session.

### Gate before Linux hardware

Record:

```text
LUT4
FF
BSRAM
DSP
Fmax
worst setup path
```

Planning limits for the plain cluster are 50% LUT, 35% BSRAM, and a passing 50 MHz constraint. They are targets, not measured results.

### Bring-up order

```text
three-core UART
  -> privilege and traps
  -> atomics and fences
  -> tagged context
  -> timer and IPI tests
  -> standalone DDR3 test
  -> shared physical memory
  -> no-MMU Linux early console
  -> BusyBox and E0 SMP
  -> framebuffer and input
  -> DOOM
```

Starting with DDR3, private coherent caches, Linux, and HDMI in one bitstream would make failures needlessly hard to locate.

## Publication rule

A board release should include source and tool revisions, exact board and FPGA revision, constraints, achieved clock, resource use, bitstream hash, UART transcript, conformance results, and known warnings. Synthesis alone is not enough; the same covered cases must agree in model, RTL, and hardware.
