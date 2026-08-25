# Roadmap

`VV32-A0` remains the working source architecture. `VV64-A0` grows from it. The tracks stay separate so Linux work does not turn the small core into an oversized compromise.

## Shared contract

**State: active**

- keep the family manifest, Python profiles, documentation, and implementation declarations in sync;
- finish generated model/RTL differential tests for `VV32-A0`;
- review current RTL warnings;
- run the formal harness in a pinned tool environment;
- begin a Sail model before `VV64-A0` encoding freezes;
- define one trace and conformance format for both widths.

## VV32-A0 hardware

**State: pre-FPGA RTL**

- close the current pre-hardware gate;
- add Tang Nano 20K clock, reset, BSRAM, UART, timer, and interrupt wiring;
- run identical binaries in the Python model, RTL simulation, and FPGA;
- publish utilization, timing, tool versions, bitstream hash, and UART transcript;
- consider tagged context memory only as a later VV32 profile.

`VV32-A0` is complete when it is a small reproducible FPGA CPU, not when the 64-bit track starts.

## VV64-A0 architecture

**State: design draft**

- freeze extension-page formats;
- specify the Capability Directory and tagged context memory;
- finish privilege, trap, atomic, and memory-ordering rules;
- specify `VTRYA`, sealed calls, protected returns, and generations;
- write an executable 64-bit model;
- add a fast emulator for compiler and kernel testing;
- implement a single-issue in-order SystemVerilog core;
- test shared family invariants against both widths.

## VV64-L0/flat Linux

**State: planned**

- create the LLVM/Clang `victoryv64` target and relocations;
- define the flat ABI and tagged context frame;
- add an out-of-tree `arch/victoryv` port with `CONFIG_MMU=n`;
- support FDPIC or FLAT loading;
- boot an initramfs to a serial shell in the emulator;
- run the same image on Tang Console 138K after DDR3 tests pass.

## VV64-L0/paged Linux

**State: planned after flat**

- freeze the `V39` page-table format;
- implement walks, TLBs, faults, and invalidation;
- preserve tags through caches and aliases;
- enable conventional ELF process mappings;
- repeat compiler, kernel, emulator, and FPGA conformance tests.

## Dual-core system

**State: later**

- place `VV32-A0` and `VV64-A0` on one 138K design only after each works alone;
- give VV32 private on-chip memory and a narrow checked mailbox;
- prevent Linux, DMA, and page tables from reaching VV32-private authority;
- demonstrate a bounded protected service.

## Stable-profile evidence

A stable profile needs generated conformance, model/RTL/FPGA differential traces, negative security tests, FPGA timing and resource results, compiler and kernel tests, and independent review.

The next implementation work is the VV32 differential gate and the first executable VV64 model.
