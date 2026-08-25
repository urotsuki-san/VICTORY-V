# VICTORY-V Architecture Family

## Lineage

`VV32-A0` is the source architecture. It is not a temporary bootstrap ISA and it will not be retired when the 64-bit work begins.

`VV64-A0` is the general-purpose continuation of the same design. It widens the integer and address state, adds operating-system machinery, and keeps the rules that make the machine VICTORY-V.

```text
VV32-A0
   ├── compact FPGA and deterministic control work
   └── shared architectural contract
            └── VV64-A0
                    ├── VV64-L0/flat   no MMU
                    └── VV64-L0/paged  V39 MMU
```

The machine-readable copy is [`isa/victory-v-family.json`](../isa/victory-v-family.json). `vv profiles` prints the same data.

## Family rules

A conforming profile keeps all of the following:

1. Memory authority is tagged. Integer arithmetic cannot manufacture a valid capability.
2. Authority is monotonic. Bounds and permissions may be narrowed, never widened by ordinary code.
3. Secret flow is visible. Secret-tagged data cannot silently select a branch, indirect target, or address.
4. Victory Regions are bounded. Store count and instruction count are known at entry.
5. `VIC` is the only successful end of a region. Failure discards staged stores and records a reason.
6. `VLOCK` closes root creation after boot setup.
7. The baseline implementation is in order and does not speculate effects into shared state.

A core that drops one of these rules is not VICTORY-V merely because it reuses an opcode map.

## What VV64 adds

`VV64-A0` adds the pieces needed by compilers and operating systems:

- 64-bit integer registers and program counter;
- Monitor, Supervisor, and User privilege;
- tagged context save and restore;
- capability-checked atomics and fences;
- sealed call gates and protected returns;
- an interrupt-abort form of Victory Region;
- an optional `V39` translation profile;
- cache and TLB rules that preserve tags and authority.

The first 64-bit core remains single-issue and in order. Floating point, vectors, SMP, and out-of-order execution are later work.

## MMU policy

Physical mode is mandatory. Page translation is optional.

When translation is enabled, effective access is the intersection of four checks:

```text
capability rights
∩ active-domain rights
∩ page-table rights
∩ current-privilege rights
```

A page table may deny an access. It may not grant authority that the capability or domain does not already hold.

This keeps the same pointer and protection model in bare metal, no-MMU Linux, and paged Linux.

## Encoding continuity

Both widths use fixed 32-bit instructions. Existing `VV32-A0` primary opcodes retain their positions. The remaining primary-opcode space is reserved by function rather than consumed ad hoc:

| Opcode | Page | Purpose |
|---:|---|---|
| `0x36` | `XALU` | division, remainder, word operations, 64-bit constant lanes |
| `0x37` | `XMEM` | 64-bit access and tagged capability spill/fill |
| `0x38` | `XATOM` | reservation, compare/exchange, atomic RMW, fences |
| `0x39` | `XCALL` | sealed entry, protected call and return |
| `0x3a` | `XSYS` | privilege, context, interrupt, and domain operations |
| `0x3b` | `XVM` | optional page translation and TLB maintenance |
| `0x3c`–`0x3f` | reserved | left unused in A0 |

The sub-opcode layouts are not frozen yet.

## Capability Directory

Full 64-bit bounds and policy fields are expensive to duplicate in every FPGA register and cache word. The draft therefore gives `VV64-A0` a protected Capability Directory.

A tagged register carries a cursor plus a non-forgeable directory reference. The directory entry contains:

```text
base, top, permissions, domain, object type, generation, sealed state
```

Reusing an entry changes its generation. A stale tagged reference then fails instead of silently acquiring authority over a new object.

`CBOUNDS` is exact-or-fail. It may reject an interval that an implementation cannot represent; it may not round the interval outward.

## Implementation tracks

The family contract does not force one microarchitecture.

- `VV32-A0` stays compact and is still aimed at Tang Nano 20K.
- The first `VV64-A0` implementation is aimed at Tang Console 138K.
- Both may later share one 138K design, but only after each works independently.

See [`VV64.md`](VV64.md), [`LINUX_PORT.md`](LINUX_PORT.md), and [`FPGA_HANDOFF.md`](FPGA_HANDOFF.md).
