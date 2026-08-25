# Native Linux Port

## Target

Linux is to run on a native `VV64-A0` processor. No RISC-V, Arm, or other host CPU is placed beside it and renamed VICTORY-V.

The first two system profiles are:

- `VV64-L0/flat`: MMU disabled, capability domains, FDPIC or FLAT userspace;
- `VV64-L0/paged`: optional `V39` translation and conventional ELF processes.

The flat profile comes first.

## Why no-MMU comes first

A 64-bit CPU does not require page translation. Linux supports no-MMU systems, but the normal ELF loader depends on `MMU`; no-MMU ports use FDPIC or FLAT-style executable formats and accept tighter process-model limits.

The first useful milestone is therefore:

```text
native VV64 core
+ privilege and interrupts
+ capability-aware compiler
+ no-MMU kernel
+ FDPIC or FLAT init
+ BusyBox over serial
```

This proves the CPU, compiler, tagged context, atomics, kernel entry, DDR, and drivers before a page walker is added to the same debug problem.

## Toolchain work

The Python assembler is for architecture tests, not Linux builds. The native port needs:

1. an LLVM target, provisionally `victoryv64`;
2. assembler and disassembler support for the extension pages;
3. an ELF machine number and relocation set;
4. `lld` support;
5. a Clang target and compiler builtins;
6. pointer lowering that preserves capability metadata;
7. startup code and a C library for the flat ABI;
8. debugger descriptions for values, tags, directory references, and secret state.

A fast emulator should be added before kernel work. The Python model remains the readable reference; the faster implementation handles compiler tests and full boots.

## Kernel port

The out-of-tree kernel port will use:

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

The first port covers reset entry, traps, timer, interrupts, syscalls, user copy, tagged context and signal frames, atomics, fences, device tree, early serial, no-MMU process setup, and FDPIC or FLAT loading.

A tagged capability must not be saved with an integer store. Context and signal frames use the `CLDC` and `CSTC` path.

## Flat process model

Each process receives a domain plus initial capabilities for code, data, stack, and kernel entry. FDPIC is a useful fit because its load segments may be placed independently in physical memory.

A context switch changes the active domain and restores tagged registers. A process cannot reach another process by guessing its physical address.

This is not virtual memory. It does not provide demand paging, copy-on-write fork, overcommit, or arbitrary sparse mappings. The target is a small, honest no-MMU Linux rather than a claim that every desktop assumption survives unchanged.

## Paged profile

`VV64-L0/paged` adds `V39`, TLB fill and invalidation, page faults, standard ELF loading, shared libraries, and conventional process mappings.

Page rights are intersected with capability and domain rights. Supervisor cannot use a page table to grant authority that Monitor never delegated.

## Boot sequence

```text
reset ROM
  -> VICTORY monitor
  -> create roots and domains
  -> VLOCK
  -> load kernel and device tree
  -> enter Supervisor
  -> Linux early console
  -> initramfs
  -> /init
```

There is no borrowed SBI or foreign firmware ABI. The monitor interface will be a small VICTORY-V contract for timer, reset, console handoff, and domain setup.

## Tang Console 138K stages

1. Run the same bare-metal corpus in the 64-bit model and RTL.
2. Boot a native core from on-chip RAM and print over UART.
3. Add timer, interrupts, tagged context switching, and directory-generation tests.
4. Add DDR3 and pass destructive memory tests before enabling caches.
5. Reach `start_kernel()` and early console with `CONFIG_MMU=n`.
6. Add FDPIC or FLAT userspace and reach a BusyBox shell.
7. Add `V39` and repeat the boot in the paged profile.
8. Only then consider placing `VV32-A0` beside the Linux core.

LiteX may supply board descriptions, interconnect, and DDR plumbing. The CPU, ISA, privilege model, monitor ABI, compiler target, and Linux architecture port remain VICTORY-V work.

## Public success criteria

A Linux claim should include exact revisions for VICTORY-V, compiler, linker, kernel, and root filesystem; emulator and FPGA transcripts; resource use and clock; DDR test results; a serial login identifying `victoryv64`; and negative tests for forged capabilities, stale generations, secret branches, and failed Victory Regions.

Until then the status is planned or in progress, not Linux-capable.
