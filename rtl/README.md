# RTL

The default RTL tree contains three CPU cores and the small range unit used by the no-MMU-first Tang 138K image.

```text
VV32-A0             budget root / monitor
VV64-A0/P0 + VRTU   main 64-bit core, four ranges
VV64-A0/E0 + VRTU   smaller worker, two ranges
```

## CPU cores

- `vv32_core.sv` — compact 32-bit control core.
- `vv64_core.sv` — native 64-bit bring-up core.
- `vv64_profiled_core.sv` — P0/E0 budgets plus VRTU integration.
- `vv32_pkg.sv`, `vv64_pkg.sv` — opcodes, CSRs, states, and fault causes.

Both widths checkpoint register and capability metadata at the `VTRY` boundary. Opcode `0x30` is `VTRY.I`, the inline form. `VPREP` followed by opcode `0x3d` is `VTRY.C`, the prepared form. The RTL symbol is `OP_VTRYC`; both encodings enter the same Region state.

Stores remain buffered until `VIC`. Repeated writes to one aligned granule merge. `ST_PREFLIGHT` checks the complete write set before `ST_COMMIT` emits the first store. Abort restores the entry state; a late publication fault is fatal because visible writes cannot honestly be called rolled back.

## VRTU

`memory/vv_vrtu.sv` is the Victory Range Translation Unit. It has independent instruction and data paths, a small exact descriptor bank, and a generation-checked last-range guard on each path.

It has no page-table walker and no software refill. Zero matches report cause 20, missing permissions report 21, overlapping matches report 22, Region access to a device range reports 27, and malformed configuration reports 31.

```bash
make rtl-test-vrtu
```

## SoCs

- `soc/vv_dual_bringup.sv` — older VV32 + raw VV64 regression.
- `soc/vv_cluster_bringup.sv` — current `VV32 + P0 + E0` image.

The cluster provides private RAM, UART, boot mailboxes, timebase, timer compares, and IPI bits. DDR3 and coherent shared memory are not connected.

## Tang 138K

The four B/C Mega/Console projects instantiate `vv_cluster_bringup` and include `memory/vv_vrtu.sv`. The ROM runs both `VTRY` forms and rollback before the expected UART transcript:

```text
VV32-A0 VTRY ready
VV64-P0 VTRY ready
VV64-E0 VTRY ready
```

Gowin place-and-route and hardware validation are still required.

## Archived experiment

The former Euclid block is under `experiments/euclid/` and is not part of the default bitstream or `make rtl-test`.

```bash
make experiment-euclid
```

## Tests

```bash
make rtl-test-vv32
make rtl-test-vv64
make rtl-test-contract-vv32
make rtl-test-contract-vv64
make rtl-test-region-irq
make rtl-test-vrtu
make rtl-test-dual
make rtl-test-cluster
make rtl-test
```
