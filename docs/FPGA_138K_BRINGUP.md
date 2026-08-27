# Tang 138K Bring-up

## Status

The default board image contains three CPU cores:

```text
VV32-A0 control
VV64-A0/P0 + VRTU-P0
VV64-A0/E0 + VRTU-E0
```

The old Euclid RTL is archived under `experiments/euclid/` and is not listed in the Gowin projects.

The source, boot ROMs, board tops, B/C Gowin projects, constraints, platform manifest, VRTU model, and self-checking RTL tests are present. No bitstream or hardware result is claimed. Gowin synthesis, placement, timing, programming, and the real UART/LED result still require the selected board.

## First image

```text
50 MHz board clock
        |
        +-- reset synchronizer
        |
        +-- VV32-A0 ---------------- 64 KiB RAM --+
        |                                         |
        +-- VV64-P0 -- 4-entry VRTU -- 64 KiB RAM +-- UART TX
        |                                         +-- mailboxes
        +-- VV64-E0 -- 2-entry VRTU -- 64 KiB RAM +-- timebase / timer
                                                  +-- software interrupts
```

The RAMs are private on purpose. DDR3, caches, arbitration, and coherence wait until first light.

Boot order is fixed:

```text
VV32-A0 -> VV64-P0 -> VV64-E0
```

Each core runs its ROM self-test before touching its mailbox. The test covers direct `VTRY` commit, prepared `VTRY` commit, and explicit rollback. P0 and E0 also attempt a Region write to the VRTU `DEVICE` window and require cause 27.

Expected UART at 115200 8N1:

```text
VV32-A0 VTRY ready
VV64-P0 VTRY ready
VV64-E0 VTRY ready
```

A failed stage prints `VTRY FAIL 1` through `VTRY FAIL 4` and halts before the normal mailbox marker.

## Contract capacity

| Core | ISA | Role | Capability Directory | Region stores | Derived capabilities | VRTU ranges |
|---|---|---|---:|---:|---:|---:|
| VV32 | `VV32-A0` | budget root / monitor | register metadata | 8 | profile-defined | — |
| P0 | `VV64-A0` | Linux boot CPU | 32 | 8 | 8 | 4 |
| E0 | `VV64-A0` | Linux worker | 8 | 2 | 2 | 2 |

P0 and E0 share one ISA. Their first meaningful difference is how large a bounded contract each can hold. `VTRY fail, stores, budget` selects the inline encoding; `VPREP` followed by `VTRY cToken, fail` selects the prepared encoding.

## VRTU reset map

| Virtual range | Physical range | Rights |
|---|---|---|
| `0x0000_0000..0x0000_ffff` | identity | `RWXU` |
| `0x0001_0000..0x0001_ffff` | identity | supervisor `RW`, device |

There is no software refill and no page-table walker. Miss, permission, and overlap faults are causes 20, 21, and 22.

## CPU MMIO page

| Address | Register | Use |
|---:|---|---|
| `0x0001_0000` | UART TX | low byte is transmitted |
| `0x0001_0010` | VV32 mailbox | boot marker `0x32` |
| `0x0001_0018` | P0 mailbox | boot marker `0x50` |
| `0x0001_0020` | E0 mailbox | boot marker `0x45` |
| `0x0001_0028` | LED register | software status |
| `0x0001_0030` | status | mailbox, halt, release, timer, IPI |
| `0x0001_0038` | timebase | free-running cycle counter |
| `0x0001_0040` | P0 timer compare | P0 interrupt |
| `0x0001_0048` | E0 timer compare | E0 interrupt |
| `0x0001_0050` | IPI set | bit 0 P0, bit 1 E0 |
| `0x0001_0058` | IPI clear | bit 0 P0, bit 1 E0 |
| `0x0001_0060` | core info | ID, class, XLEN |

The machine-readable copy is [`platform/tang-138k-1p1e1v32.json`](../platform/tang-138k-1p1e1v32.json).

## Checks

```bash
make test
make family-check
make fpga-check
make fpga-handoff-check
make docs-check
make rtl-test-contract-vv32
make rtl-test-contract-vv64
make rtl-test-vrtu
make rtl-test-cluster
make rtl-test
```

`fpga-check` verifies the three-core shape, both `VTRY` encodings in every generated ROM, rollback, the VV64 device test, VRTU 4/2 capacity, no walker or refill, exact VRTU causes, Euclid isolation, all four project source lists, and the board tops.

## Gowin project selection

| Carrier | Device B | Device C |
|---|---|---|
| Tang Mega 138K Dock | `victory_v_mega_138k_b.gprj` | `victory_v_mega_138k_c.gprj` |
| Tang Console 138K | `victory_v_console_138k_b.gprj` | `victory_v_console_138k_c.gprj` |

The projects use `GW5AST-LV138PG484AC1/I0`. Select the revision actually reported by Gowin Programmer.

## Pins

### Tang Mega 138K Dock

| Signal | Pin |
|---|---|
| 50 MHz clock | `V22` |
| UART TX | `U15` |
| UART RX | `V14` |
| user key | `F4` |
| onboard LED | `V13` |

V13 is active low and lights after all three mailbox markers arrive.

### Tang Console 138K

| Signal | Pin |
|---|---|
| 50 MHz clock | `V22` |
| UART TX | `U15` |
| UART RX | `V14` |
| reset switch `s0` | `AB13` |
| status LEDs | `D21 E21 D22 E22 F20 F19 W20 W19` |

```text
0 VV32 mailbox
1 P0 mailbox
2 E0 mailbox
3 VV32 halted
4 P0 halted
5 E0 halted
6 any core cause
7 UART busy
```

## First board session

1. Open the project matching the carrier and B/C revision.
2. Confirm `top` is the top module.
3. Run synthesis and save utilization.
4. Run place-and-route and save timing.
5. Check the 20 ns input-clock constraint.
6. Program SRAM first.
7. Open UART at 115200 8N1.
8. Reset and record the three `VTRY ready` lines and LED state.
9. Repeat reset several times.

## Resource gate

Record:

```text
LUT4
FF
BSRAM
DSP
Fmax
worst setup path
```

Planning gate:

```text
<= 50% LUT
<= 35% BSRAM
50 MHz timing passes
```

This is a planning threshold, not a measured result.

## After first light

```text
Gowin utilization / timing
  -> timer, IPI, privilege
  -> atomics and tagged context
  -> standalone DDR3 test
  -> shared uncached memory
  -> physical caches
  -> CONFIG_MMU=n early console
  -> BusyBox
  -> framebuffer and input
  -> DOOM
```
