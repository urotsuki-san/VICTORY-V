# Heterogeneous Cluster

The Tang 138K system is `1P + 1E + 1V32`.

```text
VV32-A0   budget root / monitor
VV64-P0   main core, larger contract
VV64-E0   worker, smaller contract
```

The useful difference is not a new ISA. P0 and E0 admit different footprints:

| Resource | P0 | E0 |
|---|---:|---:|
| Capability Directory | 32 | 8 |
| Region stores | 8 | 2 |
| Derived capabilities | 8 | 2 |
| VRTU ranges | 4 | 2 |

Both cores run the same instructions. A prepared `VTRY` can be admitted against a profile before work starts; a job that does not fit E0 can be sent to P0 without changing the binary.

## First image

Each core has private 64 KiB RAM. UART, mailboxes, timebase, timer compares, and IPI bits are shared through the MMIO page. P0 and E0 reach RAM and MMIO through VRTU. VV32 remains outside the Linux scheduler.

The default image has no DDR3, cache coherence, or shared SMP memory.

## Boot

```text
reset -> VV32 mailbox -> release P0 -> P0 mailbox -> release E0
```

Each core reaches its mailbox only after direct `VTRY`, prepared `VTRY`, and rollback checks. Expected UART:

```text
VV32-A0 VTRY ready
VV64-P0 VTRY ready
VV64-E0 VTRY ready
```
