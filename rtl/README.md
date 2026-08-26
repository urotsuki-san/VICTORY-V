# VICTORY-V RTL

The RTL directory contains two architectures, two VV64 implementation profiles, and two bring-up SoCs.

## Cores

### `vv32_core.sv`

`VV32-A0` is the compact core. It is single-issue, in-order, and multi-cycle. Capability metadata and Secret Tags live beside the register file. Victory Regions use a bounded store buffer.

VV32 remains part of the system. On the Tang 138K target it is the control core, not a discarded 64-bit prototype.

### `vv64_core.sv`

The VV64 core is the current FPGA subset of `VV64-A0`. It keeps the VV32 primary opcode positions and widens registers, PC, CSRs, and the data port to 64 bits.

Implemented:

- base integer and control instructions;
- byte, halfword, word, and doubleword capability memory access;
- a generation-checked Capability Directory;
- Secret Tags;
- `VLOCK`;
- bounded Victory Regions with forwarding, commit, rollback, and secret scrub;
- basic CSRs, traps, an interrupt input, and `WFI`.

Still missing:

- Monitor/Supervisor/User privilege;
- tagged capability spill/fill;
- atomics and fences;
- sealed calls and protected returns;
- `VTRYA`;
- caches, DDR3, and page translation.

Unsupported extension-page operations trap as illegal instructions.

## P0 and E0

`vv64_profiled_core.sv` wraps the same ISA core with two resource envelopes.

| Profile | Capability Directory | Region store buffer |
|---|---:|---:|
| P0 | 32 | 8 |
| E0 | 8 | 2 |

This is the first implementation split. It is enough to instantiate and test 1P1E on the FPGA. The arithmetic pipeline and memory path are still shared. Later work may give P0 larger caches and faster arithmetic while E0 stays smaller.

## SoCs

### `soc/vv_dual_bringup.sv`

The original VV32+VV64 image remains as a regression test.

### `soc/vv_cluster_bringup.sv`

The current Tang 138K board image contains:

```text
VV32-A0 + VV64-P0 + VV64-E0
```

Each core has private BRAM. They share UART, mailboxes, a timebase, per-VV64 timer compares, software interrupt bits, and status LEDs. Boot order is VV32, P0, E0.

Expected UART output:

```text
VV32-A0 ready
VV64-P0 ready
VV64-E0 ready
```

This proves the three-core topology. It does not provide shared memory or SMP Linux yet.

## Tests

```bash
make rtl-test-vv32
make rtl-test-vv64
make rtl-test-dual
make rtl-test-cluster
```

Run all RTL tests with:

```bash
make rtl-test
```

Board projects and constraints are under `fpga/tang-138k/`.
