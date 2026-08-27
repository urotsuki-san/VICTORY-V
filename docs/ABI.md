# ABI Notes

No stable userspace ABI exists yet.

The first target is `VV64-L0-flat`:

```text
64-bit little-endian
CONFIG_MMU=n
FDPIC or FLAT userspace
VRTU protected ranges
```

A process layout must fit the available VRTU range capacity. P0 has four ranges; E0 has two. Monitor programs the ranges, checks that they do not overlap, and locks the bank before entering a less privileged level.

The tagged context format, syscall convention, stack alignment, TLS, signal frame, atomics, and relocation set remain open. The prepared `VTRY` token format is architectural register metadata, not a userspace ABI yet.

The archived Euclid experiment has no opcode, CSR, MMIO page, or ABI.
