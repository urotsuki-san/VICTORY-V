# FPGA Targets and Handoff Gates

VICTORY-V has two hardware tracks and one shared 138K bring-up image. The shared image is a test fixture, not a claim that the two cores already form a complete heterogeneous system.

## VV32-A0 — Tang Nano 20K

### Pre-hardware gate

- [x] fixed instruction encoding and machine-readable manifest;
- [x] assembler and binary image generation;
- [x] executable Python model;
- [x] capability, secret-flow, commit, rollback, quota, and budget tests;
- [x] board-independent SystemVerilog core;
- [x] self-checking RTL smoke test;
- [x] public CI definition;
- [ ] RTL warnings reviewed with the selected Gowin tool version;
- [ ] generated Python/RTL differential traces pass;
- [ ] formal checks pass with pinned tool versions;
- [ ] Tang Nano 20K clock, reset, RAM, UART, and constraints are committed.

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

External SDRAM, caches, HDMI, and Linux stay out of the first VV32 bitstream.

## VV64-A0 — Tang Mega / Console 138K

The 138K target uses a native VICTORY-V core. The current RTL is a bring-up subset: enough to exercise 64-bit execution, the Capability Directory, capability memory checks, Secret Tags, Victory Regions, UART, and on-chip RAM. It is not yet the full operating-system profile.

### Pre-hardware gate

- [x] inherited base opcode positions fixed for the prototype;
- [x] 64-bit integer/control and doubleword memory RTL;
- [x] protected Capability Directory with generation checks;
- [x] Secret Tags, `VLOCK`, and Victory Regions in RTL;
- [x] self-checking VV64 core simulation;
- [x] fixed physical-mode boot ROM and MMIO map;
- [x] board clock/reset, UART, LED, and constraints for Mega and Console 138K;
- [x] VV32/VV64 co-resident simulation;
- [ ] Gowin synthesis warnings reviewed;
- [ ] place-and-route passes the 50 MHz constraint;
- [ ] UART output and status LEDs confirmed on hardware;
- [ ] generated model/RTL differential corpus;
- [ ] tagged context save and restore;
- [ ] Monitor/Supervisor/User privilege, timer, and interrupts;
- [ ] atomics, fences, sealed calls, and `VTRYA`;
- [ ] DDR3 controller tested independently.

### Current 138K image

```text
VV32 ROM -> VV32 core -> private 64 KiB RAM --+
                                                +-> UART / mailboxes / LEDs
VV64 ROM -> VV64 core -> private 64 KiB RAM --+
```

VV32 starts first. VV64 is released after the VV32 mailbox or a timeout. This keeps the UART transcript readable and gives each core a simple failure boundary.

See [`FPGA_138K_BRINGUP.md`](FPGA_138K_BRINGUP.md) for projects, pins, MMIO, and the first board session.

### Bring-up order after hardware confirmation

```text
on-chip RAM + UART
  -> timer and interrupts
  -> tagged context switch
  -> generation and sealed-call tests
  -> Victory Region and VTRYA tests
  -> DDR3 memory test
  -> no-MMU Linux early console
  -> FDPIC or FLAT userspace
  -> V39 later
```

Starting with DDR3, caches, page translation, and Linux in one bitstream would make failures needlessly hard to locate.

## Publication rule

A board release should include source and tool revisions, exact board and FPGA revision, constraints, achieved clock, resource use, bitstream hash, UART transcript, conformance results, and known warnings. Synthesis alone is not enough; the same covered cases must agree in the model, RTL, and hardware.
