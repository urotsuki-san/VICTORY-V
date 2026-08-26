# VICTORY-V Architecture Family

## Lineage

`VV32-A0` is the source architecture. It is not a temporary bootstrap ISA and it will not be retired as the 64-bit work grows.

`VV64-A0` is the general-purpose continuation of the same design. It widens integer and address state, adds the machinery needed by an operating system, and keeps the rules that make the machine VICTORY-V.

```text
VV32-A0
   ├── compact FPGA and deterministic control work
   └── shared architectural contract
            └── VV64-A0
                    ├── P0 / E0 implementation profiles
                    ├── VV64-L0/flat   no page translation
                    └── VV64-L0/paged  V39 later
```

P0 and E0 are not new ISAs. They execute the same `VV64-A0` binaries with different hardware budgets.

The machine-readable architecture copy is [`isa/victory-v-family.json`](../isa/victory-v-family.json). The Tang 138K system copy is [`platform/tang-138k-1p1e1v32.json`](../platform/tang-138k-1p1e1v32.json).

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

The full `VV64-A0` contract adds:

- 64-bit integer registers and program counter;
- Monitor, Supervisor, and User privilege;
- tagged context save and restore;
- capability-checked atomics and fences;
- sealed call gates and protected returns;
- an interrupt-abort form of Victory Region;
- optional `V39` translation;
- cache and TLB rules that preserve tags and authority.

The first FPGA subset implements the widened base machine, a protected Capability Directory, Secret Tags, Victory Regions, `VLOCK`, doubleword memory access, and basic trap/interrupt state. The operating-system extensions remain visible as missing work rather than empty stubs.

## Translation policy

Physical mode is mandatory. Page translation is optional.

When translation is enabled, effective access is the intersection of four checks:

```text
capability rights
∩ active-domain rights
∩ page-table rights
∩ current-privilege rights
```

A page table may deny an access. It may not grant authority that the capability or domain does not already hold.

This keeps the same pointer and protection model in bare metal, no-MMU Linux, and a later paged Linux profile.

## Encoding continuity

Both widths use fixed 32-bit instructions. Existing `VV32-A0` primary opcodes retain their positions. The remaining primary-opcode space is reserved by function:

| Opcode | Page | Purpose |
|---:|---|---|
| `0x36` | `XALU` | division, remainder, word operations, 64-bit constant lanes |
| `0x37` | `XMEM` | doubleword and tagged context memory operations |
| `0x38` | `XATOM` | reservation, compare/exchange, atomic RMW, fences |
| `0x39` | `XCALL` | sealed entry, protected call and return |
| `0x3a` | `XSYS` | privilege, context, interrupt, and domain operations |
| `0x3b` | `XVM` | optional page translation and TLB maintenance |
| `0x3c`–`0x3f` | reserved | left unused in A0 |

The FPGA subset assigns only `XMEM.CLDD` and `XMEM.CSTD`. Other sub-opcodes are still open.

## Capability Directory

Full 64-bit bounds and policy fields are expensive to duplicate in every FPGA register and cache word. `VV64-A0` therefore uses a protected Capability Directory.

A tagged register carries a cursor plus a non-forgeable directory reference. The first RTL directory stores:

```text
base, top, permissions, validity, generation
```

The full architecture will add domain, object type, and sealing state. Reusing an entry changes its generation. A stale tagged reference then fails instead of silently acquiring authority over a new object.

`CBOUNDS` is exact-or-fail. It may reject an interval that an implementation cannot represent; it may not round the interval outward.

## Implementation tracks

- `VV32-A0` remains the compact track and still targets Tang Nano 20K.
- `VV64-A0` is a separate native architecture, not a widened build flag on VV32.
- P0 and E0 share the VV64 ISA and ABI. The first wrappers differ in Capability Directory and Victory Region buffer size.
- The Tang 138K image instantiates VV32, P0, and E0 with private RAM and a shared UART/control page.
- VV32 remains the monitor and control core. It is not a Linux LITTLE core.
- Co-residence currently proves wiring and boot order only. It does not imply coherent shared memory or completed SMP Linux.

See [`VV64.md`](VV64.md), [`HETEROGENEOUS_CLUSTER.md`](HETEROGENEOUS_CLUSTER.md), [`LINUX_PORT.md`](LINUX_PORT.md), [`FPGA_HANDOFF.md`](FPGA_HANDOFF.md), and [`FPGA_138K_BRINGUP.md`](FPGA_138K_BRINGUP.md).
