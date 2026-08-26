# 1P1E + VV32 Cluster

## The point of the split

The Tang 138K target uses three cores:

```text
core 0  VV32-A0 control core
core 1  VV64-A0/P0 performance profile
core 2  VV64-A0/E0 efficient profile
```

VV32 is not a discarded first attempt and it is not a 64-bit stepping stone. It has a different job. The VV64 pair runs the general-purpose system; VV32 stays small and predictable.

P0 and E0 use the same `VV64-A0` ISA and ABI. Linux may eventually move a task between them without changing the executable. VV32 has its own ABI and stays outside the Linux scheduler.

## What P0 and E0 mean today

The first split is deliberately modest.

| Item | P0 | E0 |
|---|---:|---:|
| ISA | `VV64-A0` | `VV64-A0` |
| Capability Directory | 32 entries | 8 entries |
| Victory Region store buffer | 8 entries | 2 entries |
| Local bring-up RAM | 64 KiB | 64 KiB |
| Execution engine | current VV64 core | current VV64 core |

This is enough to make the profile boundary real and test it on the board. It does not yet prove that P0 is faster or that E0 uses less power. Those claims wait for Gowin reports and hardware measurements.

The next split should happen inside the implementation, not in the ISA:

- P profile: larger physical caches, faster multiply/divide, stronger branch handling;
- E profile: smaller caches, iterative arithmetic, shallower queues;
- both: identical traps, atomics, context format, Capability rules, and Linux ABI.

## VV32's job

The control core is intended for work that should not depend on Linux being healthy:

- reset and boot sequencing;
- watchdog and crash recovery;
- UART and simple I/O service;
- board health checks;
- trusted mailboxes;
- capability-domain setup;
- optional clock and reset control for the VV64 pair.

A later system may reset the VV64 cluster while VV32 keeps running. Shared mutable memory is not required for that. A narrow mailbox protocol is easier to inspect and harder to misuse.

## Current bring-up topology

```text
VV32-A0  -> private BRAM --+
VV64-P0  -> private BRAM --+-- UART
VV64-E0  -> private BRAM --+-- mailboxes
                            +-- timebase / timer compare
                            +-- software interrupt bits
                            +-- status LEDs
```

Boot order is fixed:

```text
VV32-A0 -> VV64-P0 -> VV64-E0
```

Each stage writes a marker before the next core is released. Timeouts prevent a dead core from holding the rest of the image in reset forever.

The three private RAMs are a bring-up convenience. They are not the Linux memory model.

## Linux topology

The first Linux target is `VV64-L0/flat` with `CONFIG_MMU=n`.

```text
VV64-P0  boot CPU, interrupts, kernel foreground, DOOM
VV64-E0  secondary CPU, background and service work
VV32-A0  monitor, watchdog, I/O and recovery
```

P0 and E0 need:

- the same architectural context layout;
- atomics and fences;
- per-core timer and interrupt state;
- an inter-processor interrupt path;
- a shared physical memory fabric;
- coherent data access or a deliberately uncached first SMP mode.

The current RTL already provides a timebase, two timer-compare registers, software interrupt bits, core information, and a release chain. Privilege, atomics, tagged context save/restore, shared DDR, and cache coherence remain open.

## First shared-memory rule

Do not begin with private write-back caches and a home-grown MESI protocol.

The first SMP Linux image should use one of these:

1. uncached shared DDR for both VV64 cores;
2. a single shared data cache in front of DDR;
3. private instruction caches and uncached shared data.

It will be slower, but it keeps the memory model understandable. Private coherent data caches can follow after Linux boots reliably.

VV32 should continue to use mailboxes or a small uncached window rather than joining the Linux coherent domain.

## Resource gates

The 138K build must be measured before caches and DDR are added.

For the first three-core image, record:

```text
LUT4
flip-flops
BSRAM
DSP
Fmax
worst timing path
```

A useful first gate is:

```text
cluster bring-up:  <= 50% LUT, <= 35% BSRAM, 50 MHz timing passes
pre-Linux system:  <= 70% LUT, <= 70% BSRAM
```

These are planning limits, not device guarantees. If the plain bring-up image already crosses them, P0/E0 must be simplified before DDR and video are attached.

## Public proof

A three-core claim should include:

- the exact bitstream source commit;
- Gowin and device revisions;
- utilization and timing reports;
- the three UART lines in order;
- mailbox and LED results;
- negative tests for a dead P0 or E0 release stage;
- later, Linux output showing P0 and E0 as VV64 CPUs and VV32 as the control core.
