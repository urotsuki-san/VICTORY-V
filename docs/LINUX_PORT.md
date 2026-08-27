# Linux Port

## First target

The first port is native `VV64-A0` with:

```text
CONFIG_MMU=n
P0 boot CPU
E0 optional secondary CPU
VV32 outside the scheduler
VRTU flat range protection
```

No-MMU is a sequencing decision, not an excuse to skip protection. VRTU checks a small exact set of ranges without a refill handler or page walk.

## Why VRTU first

The first board has private on-chip RAM and a small MMIO window. Four P0 descriptors can cover kernel/text, data, stack/heap, and the device window without adding a TLB, page-table format, walker, replacement policy, or miss trap.

E0 has two entries and suits a smaller fixed worker layout.

## Required kernel work

1. toolchain target and ELF relocation rules;
2. Monitor/Supervisor/User state;
3. trap frame and interrupt entry;
4. tagged context save/restore;
5. timer and IPI support;
6. atomics/fences or an explicitly uniprocessor first port;
7. VRTU context programming and lock;
8. flat userspace loader;
9. early console and initramfs.

The current RTL uses a locked reset map because privilege firmware does not yet exist. The VRTU configuration port is present for the later Monitor path.

## Boot order

```text
VV32 monitor
  -> release P0
  -> P0 early console
  -> release E0 after SMP rules exist
```

P0 is the first Linux and DOOM target. E0 should not join until shared memory, interrupts, and atomic ordering are real. The bring-up ROM already checks both `VTRY` encodings, but it is not a scheduler or context-switch test.

## Paged profile

`VV64-L0-paged` remains planned. Add it after measuring the no-MMU system and identifying a concrete requirement that VRTU cannot serve.

The archived Euclid experiment is unrelated to the Linux boot path and is not in the FPGA image.
