# FPGA Targets and Handoff Gates

## Tang 138K default image

```text
VV32-A0 control / budget root
VV64-A0/P0 + four-entry VRTU
VV64-A0/E0 + two-entry VRTU
private RAM, UART, mailboxes, timer, IPI
```

Euclid is not in the default image. Its source is isolated under `experiments/euclid/`.

### Pre-hardware gate

- [x] VV32 and VV64 fixed-width RTL cores;
- [x] complete register, capability, and VV64 Directory rollback;
- [x] direct and prepared `VTRY` paths;
- [x] one-shot token admission and stale-copy rejection;
- [x] write-set merge and all-entry commit preflight;
- [x] Region device rejection and fixed-release secret contracts;
- [x] P0/E0 profile wrapper;
- [x] exact VRTU model and RTL;
- [x] VRTU miss, permission, conflict, configuration, and generation tests;
- [x] 4-entry P0 and 2-entry E0 range capacity;
- [x] no software refill and no page-table walker;
- [x] three-core boot ROM with direct/prepared `VTRY`, rollback, and VV64 device checks;
- [x] UART and mailbox simulation after those checks;
- [x] Mega/Console B/C Gowin projects;
- [x] Euclid absent from all four projects and board tops;
- [x] platform, ISA, documentation, and project consistency checks;
- [ ] Gowin warnings reviewed;
- [ ] utilization recorded;
- [ ] 50 MHz place-and-route passes;
- [ ] bitstream programmed;
- [ ] three UART lines confirmed on hardware.

## Commands

```bash
make check
```

The command runs Python tests, examples, manifest checks, project checks, documentation checks, ISA synchronization, and the self-checking RTL suite. Icarus Verilog is required for RTL.

## Board projects

```text
fpga/tang-138k/victory_v_console_138k_b.gprj
fpga/tang-138k/victory_v_console_138k_c.gprj
fpga/tang-138k/victory_v_mega_138k_b.gprj
fpga/tang-138k/victory_v_mega_138k_c.gprj
```

Each project includes `rtl/memory/vv_vrtu.sv` and `rtl/soc/vv_cluster_bringup.sv`.

## Expected output

```text
VV32-A0 VTRY ready
VV64-P0 VTRY ready
VV64-E0 VTRY ready
```

## Publication record

A hardware release must include the source SHA, board and device revision, Gowin version, constraints, utilization, achieved clock, worst path, bitstream hash, UART transcript, and known warnings. The ready strings mean the ROM self-tests completed in that run. Source and simulation alone are still not a hardware pass.
