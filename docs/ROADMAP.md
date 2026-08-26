# Roadmap

`VV32-A0` and `VV64-A0` are two permanent tracks. VV32 stays small. VV64 carries the general-purpose system and Linux.

The Tang 138K target joins them as:

```text
VV32-A0 control + VV64-P0 + VV64-E0
```

## R0 — Three-core board bring-up

**State: RTL and simulation present**

- synthesize the 1P1E+VV32 image with Gowin;
- record LUT, FF, BSRAM, DSP, Fmax, and the worst timing path;
- program SRAM on Tang Mega or Console 138K;
- capture the three UART lines in order;
- repeat reset and release-failure tests;
- keep the original two-core simulation as a regression.

Exit condition:

```text
VV32-A0 ready
VV64-P0 ready
VV64-E0 ready
```

with no core cause and the 50 MHz constraint passing.

## R1 — VV64 system instructions

**State: next**

- add Monitor, Supervisor, and User modes;
- freeze trap and interrupt frames;
- add syscall and return;
- add atomics and fences;
- add tagged capability save/restore;
- add per-core interrupt mask and acknowledgement;
- exercise timer and IPI on P0 and E0;
- write the executable VV64 model and fast emulator.

Exit condition: two VV64 cores run context, atomic, IPI, and migration tests in model and RTL.

## R2 — DDR3 and shared memory

**State: planned**

- run the vendor DDR3 controller as a standalone destructive memory test;
- connect P0 and E0 through a simple physical-memory fabric;
- begin uncached or with one shared data cache;
- add private instruction caches;
- define DMA and framebuffer authority;
- keep VV32 on a mailbox/control window rather than the Linux coherent domain.

Exit condition: both VV64 cores pass shared-memory stress on hardware.

## R3 — Toolchain

**State: planned**

- add the LLVM `victoryv64` backend;
- add assembler, disassembler, relocations, and `lld` support;
- define the no-MMU calling convention, TLS, and tagged context layout;
- run compiler tests in the fast emulator;
- bring up a small C library.

Exit condition: freestanding C and a multi-threaded runtime pass in the emulator and FPGA test monitor.

## R4 — VV64-L0/flat Linux

**State: planned**

- add out-of-tree `arch/victoryv` support;
- boot P0 with `CONFIG_MMU=n`;
- reach early console;
- load initramfs;
- run `/init` and BusyBox;
- release E0 and pass SMP stress;
- add the VV32 mailbox/watchdog driver.

Exit condition: a repeatable serial shell with P0 and E0 online and VV32 reported as the control core.

## R5 — Video, input, and DOOM

**State: planned**

- add DDR framebuffer scanout and HDMI timing;
- add a Linux framebuffer driver;
- bring up UART or keyboard input;
- run `doomgeneric` in the emulator;
- run it on P0 while E0 stays online;
- use VV32 for watchdog and optional input service;
- demonstrate recovery from a deliberate VV64 crash.

Exit condition: a playable level over HDMI with recorded frame rate and complete build revisions.

## R6 — P/E divergence

**State: after Linux boots**

- give P0 larger caches and faster multiply/divide;
- give E0 smaller caches and iterative arithmetic;
- keep ISA, ABI, traps, atomics, context, and memory ordering identical;
- measure area, Fmax, and workload placement instead of naming cores by guesswork.

## R7 — Optional V39

**State: later**

- freeze the page-table format;
- add page walks, TLBs, faults, and invalidation;
- intersect page rights with capability and domain rights;
- repeat the compiler, kernel, emulator, and FPGA tests.

`V39` is an extension of the working no-MMU system, not a prerequisite for it.

## VV32-A0 track

VV32 work continues in parallel:

- Tang Nano 20K board integration;
- model/RTL/FPGA differential traces;
- timer and interrupt support;
- formal checks in a pinned tool environment;
- control-core mailbox and watchdog firmware for the 138K system.

VV32 is complete when it is a reproducible small FPGA CPU and a useful control core.
