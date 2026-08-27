# VRTU — Victory Range Translation Unit

## Purpose

The first Linux target remains `CONFIG_MMU=n`, but no-MMU does not have to mean unprotected. VRTU is a small exact range translator on the VV64 instruction and data buses.

It is closer to a range MPU with an offset than to a conventional page MMU:

```text
virtual address in [vbase, vtop)
physical address = pbase + (virtual address - vbase)
```

When `pbase == vbase`, VRTU only protects. When they differ, it also translates.

## Why there is no refill path

A software-refilled TLB gives a fast common case and a large, workload-dependent miss path. VRTU has no software refill trap and no page-table walker. Its descriptor bank is the complete mapping.

The Tang 138K profiles are:

| Profile | Entries | Implemented PA bits |
|---|---:|---:|
| P0 | 4 | 17 |
| E0 | 2 | 17 |

Every request ends as one of:

1. a 32-bit-generation last-range guard hit;
2. exactly one descriptor match;
3. an exact fault.

Overlapping mappings have no priority rule. They are rejected.

## Descriptor

```text
valid
generation[31:0]
vbase
vtop             ; exclusive
pbase
permissions      ; R W X U DEVICE
```

The CPU supplies the complete logical access size, not merely the aligned bus beat. User/supervisor state is explicit. A selected `DEVICE` descriptor is rejected while a Victory Region is active.

The configuration port checks a candidate before it becomes visible:

- the range is non-empty and does not overflow;
- the translated physical end fits the implemented PA width;
- no other valid descriptor overlaps it;
- `DEVICE` and `X` are not combined;
- a parent-authorized update stays inside the parent range and permissions;
- the 32-bit generation will not wrap.

A failed update leaves the old descriptor intact and reports `VRTU_CONFIGURATION`.

The first board image uses a locked reset map:

| Virtual range | Physical range | Rights | Use |
|---|---|---|---|
| `0x00000..0x10000` | same | `RWXU` | private RAM and boot ROM |
| `0x10000..0x20000` | same | supervisor `RW DEVICE` | MMIO and root window |

Later Monitor firmware may use the same module unlocked, derive a layout from a parent capability, then close it before entering Supervisor.

## Faults

| Cause | Name | Meaning |
|---:|---|---|
| 20 | `VRTU_MISS` | no range covers the complete access |
| 21 | `VRTU_PERMISSION` | range exists but lacks the requested right |
| 22 | `VRTU_CONFLICT` | more than one range covers the access |
| 27 | `REGION_DEVICE` | an active Region selected a device range |
| 31 | `VRTU_CONFIGURATION` | descriptor admission failed |

A data fault before publication aborts the Region, restores its checkpoint, and discards the write set. `VIC` uses the same path in probe mode to validate the whole set before writes begin.

## What survived from Euclid

The nearest-neighbour engine is retired from the FPGA image. Two ideas were worth keeping:

- **guarded reuse** — the previous exact range may be reused only while its bounds and generation still prove the result;
- **exact early rejection** — stop as soon as miss, permission failure, or conflict is certain.

VRTU never selects a “nearest” mapping and never returns an approximate translation.

## Current evidence

- `src/victory_v/vrtu.py` — executable exact-range model;
- `tests/test_vrtu.py` — miss, permission, conflict, offset, lock, generation, configuration, parent attenuation, device, and guard invalidation;
- `rtl/memory/vv_vrtu.sv` — synthesizable dual-path RTL;
- `rtl/tb/vv_vrtu_tb.sv` — self-checking RTL test;
- `rtl/vv64_profiled_core.sv` — P0/E0 size, privilege, probe, and device wiring;
- all four Tang 138K Gowin projects include VRTU and exclude the retired datapath.

Gowin LUT/FF/Fmax and real-board behavior remain unmeasured until the selected B/C project is synthesized, placed, routed, programmed, and observed.
