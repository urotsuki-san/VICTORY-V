# Native Linux Port

## Target

Linux runs on native `VV64-A0`. No foreign host CPU sits beside it and gets renamed VICTORY-V.

The Tang 138K system has:

```text
VV64-P0  Linux boot CPU
VV64-E0  Linux secondary CPU
VV32-A0  monitor and control core
```

P0 and E0 use the same ISA and userspace ABI. VV32 remains outside the Linux scheduler.

The first Linux profile is `VV64-L0/flat`:

```text
CONFIG_MMU=n
physical addressing
capability domains
FDPIC or FLAT userspace
```

`VV64-L0/paged` and `V39` come later.

## Why no-MMU comes first

The CPU does not need page translation to be 64-bit or to enforce authority. VICTORY-V checks capabilities and domains directly.

Starting without an MMU removes the page walker, TLB, page-fault path, and virtual-memory debugging from the first kernel boot. It does not make Linux easy. The port still needs privilege, traps, atomics, tagged context, DDR, a compiler, a linker, and userspace support.

The first useful stack is:

```text
VV64-P0/E0
+ Monitor/Supervisor/User
+ atomics and fences
+ tagged context
+ timer and IPI
+ DDR3
+ LLVM/lld
+ no-MMU kernel
+ initramfs
+ BusyBox
```

## Core roles

### P0

P0 is the boot CPU. It handles early console, kernel initialization, interrupt setup, and the first user process. It is also the first DOOM target.

### E0

E0 starts from a release mailbox after P0 is ready. It must present the same architectural context, trap behaviour, atomics, and memory ordering as P0. Linux may schedule ordinary VV64 tasks on either core.

The first P0/E0 wrappers only differ in Capability Directory and Victory Region buffer size. Cache and arithmetic differences come after the base SMP contract works.

### VV32

VV32 owns the narrow control plane:

- initial reset sequencing;
- watchdog;
- board health and simple I/O;
- crash mailbox;
- optional VV64-cluster reset;
- capability-domain setup before handoff.

Linux talks to it through a small driver. It is not a third Linux CPU.

## Hardware work still required

The current cluster already wires boot mailboxes, a timebase, per-VV64 timer compares, IPI set/clear bits, core information, and a shared UART.

Linux still requires:

1. Monitor, Supervisor, and User modes;
2. syscall and return instructions;
3. complete trap and interrupt frames;
4. tagged `CLDC`/`CSTC` context save and restore;
5. compare/exchange, atomic RMW, and fences;
6. per-core interrupt masking and acknowledgement;
7. shared DDR3;
8. a defined SMP memory model;
9. instruction and data caches or a slow uncached first build;
10. framebuffer, SD, and input drivers.

A tagged capability must never be saved with an integer store.

## Shared-memory bring-up

Do not start with private coherent write-back caches.

The first SMP kernel should use uncached shared DDR or one shared data cache. Private instruction caches are fine. Once both CPUs survive stress tests, private data caches and a coherence protocol can be added.

The first tests should include:

- atomic increment from both cores;
- spinlock handoff;
- IPI ping-pong;
- timer interrupts on both cores;
- context migration between P0 and E0;
- stale Capability Directory generation rejection after migration;
- repeated Victory Region aborts under interrupt load.

## Toolchain work

The Python assembler is a reference tool, not a Linux compiler.

The native toolchain needs:

1. an LLVM target, provisionally `victoryv64`;
2. assembler and disassembler support for the extension pages;
3. an ELF machine number and relocation set;
4. `lld` support;
5. Clang builtins and calling convention;
6. capability-aware pointer lowering;
7. TLS and per-CPU access;
8. startup code and a no-MMU C library;
9. debugger descriptions for values, tags, and directory references.

A fast emulator comes before the kernel. The Python model remains the readable reference; the faster emulator runs compiler suites and full boots.

## Kernel tree

The out-of-tree port will use:

```text
arch/victoryv/
├── Kconfig
├── Makefile
├── boot/
├── include/asm/
├── kernel/
├── lib/
└── mm/
```

The first port covers reset entry, traps, timer, IPI, SMP bring-up, syscalls, user copy, tagged context and signal frames, atomics, fences, device tree, early serial, no-MMU process setup, and FDPIC or FLAT loading.

## Flat process model

Each process receives a domain and initial capabilities for code, data, stack, and kernel entry. FDPIC is attractive because load segments may be placed independently in physical memory.

This does not provide demand paging, copy-on-write fork, overcommit, or arbitrary sparse mappings. The goal is a small no-MMU Linux that says exactly what it supports.

## Boot sequence

```text
reset
  -> VV32 monitor
  -> release P0
  -> create roots and domains
  -> VLOCK
  -> initialize DDR3
  -> load kernel, initramfs, and device tree
  -> enter Supervisor on P0
  -> Linux early console
  -> release E0
  -> SMP online
  -> /init
  -> BusyBox shell
```

There is no borrowed SBI. The monitor ABI is a small VICTORY-V contract for reset, timer handoff, console handoff, and domain setup.

## Milestones

```text
L0  P0 prints from BRAM
L1  P0 enters Supervisor and handles a timer interrupt
L2  atomics, tagged context, and user entry pass in the emulator
L3  DDR3 passes destructive tests on hardware
L4  start_kernel() reaches early console with CONFIG_MMU=n
L5  initramfs runs /init
L6  BusyBox shell over serial
L7  E0 comes online and passes SMP stress
L8  framebuffer and input drivers work
L9  doomgeneric runs on P0 while E0 remains online
```

## Public success criteria

A Linux claim should include exact revisions for VICTORY-V, compiler, linker, kernel, and root filesystem; emulator and FPGA logs; resource use and clock; DDR test results; a serial login identifying `victoryv64`; both VV64 cores online; the VV32 control driver; and negative tests for forged capabilities, stale generations, secret branches, and failed Victory Regions.

Until those logs exist, the status remains planned or in progress.
