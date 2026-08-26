# Tang 138K Bring-up

## Status

The board image now has three cores:

```text
VV32-A0 control
VV64-A0/P0
VV64-A0/E0
```

The source, boot ROMs, board tops, Gowin projects, platform manifest, and self-checking simulation are present. No bitstream or hardware result is claimed yet. Gowin synthesis, placement, timing, programming, and the UART transcript still require the toolchain and the board.

P0 and E0 use the same ISA. The first implementation split is small but real: P0 has a 32-entry Capability Directory and an 8-entry Victory Region store buffer; E0 uses 8 and 2. The execution engine is still shared.

## First image

```text
50 MHz board clock
        |
        +-- reset synchronizer
        |
        +-- VV32-A0 ---- 64 KiB RAM --+
        |                              |
        +-- VV64-P0 ---- 64 KiB RAM --+-- UART TX
        |                              +-- mailboxes
        +-- VV64-E0 ---- 64 KiB RAM --+-- timebase / timer compare
                                       +-- software interrupts
                                       +-- status LEDs
```

The RAMs are private on purpose. Shared DDR, caches, arbitration, and coherence would make first-power-on failures harder to locate.

Boot order is fixed:

```text
VV32-A0 -> VV64-P0 -> VV64-E0
```

VV32 starts at reset. Its mailbox releases P0. The P0 mailbox releases E0. Each stage also has a timeout.

Expected UART output:

```text
VV32-A0 ready
VV64-P0 ready
VV64-E0 ready
```

Default serial settings are 115200 baud, 8 data bits, no parity, one stop bit.

## Bring-up profiles

| Core | ISA | Role | Capability Directory | Region stores |
|---|---|---|---:|---:|
| VV32 | `VV32-A0` | control and monitor | register metadata | 8 |
| P0 | `VV64-A0` | Linux boot CPU | 32 | 8 |
| E0 | `VV64-A0` | Linux secondary CPU | 8 | 2 |

The P0/E0 names describe implementation budgets. They do not add opcodes or change the ABI.

## MMIO page

| Address | Register | Use |
|---:|---|---|
| `0x0001_0000` | UART TX | low byte is transmitted |
| `0x0001_0010` | VV32 mailbox | boot marker `0x32` |
| `0x0001_0018` | P0 mailbox | boot marker `0x50` |
| `0x0001_0020` | E0 mailbox | boot marker `0x45` |
| `0x0001_0028` | LED register | software status value |
| `0x0001_0030` | status | mailboxes, halt, release, lock, timer, IPI |
| `0x0001_0038` | timebase | free-running cycle counter |
| `0x0001_0040` | P0 timer compare | raises the P0 interrupt input |
| `0x0001_0048` | E0 timer compare | raises the E0 interrupt input |
| `0x0001_0050` | IPI set | bit 0 P0, bit 1 E0 |
| `0x0001_0058` | IPI clear | bit 0 P0, bit 1 E0 |
| `0x0001_0060` | core info | ID, class, and XLEN for the requester |

The timer and IPI registers are wiring for the Linux path. The current boot ROM does not enable interrupts.

The machine-readable copy is [`platform/tang-138k-1p1e1v32.json`](../platform/tang-138k-1p1e1v32.json).

## Simulation

```bash
make fpga-check
make rtl-test-cluster
```

The full RTL target also keeps the old two-core regression:

```bash
make rtl-test
```

`fpga-check` verifies:

- inherited VV32 opcode positions did not move in VV64;
- the generated ROM is current;
- the platform really contains VV32, P0, and E0 in that order;
- P0 has a larger resource envelope than E0;
- all Gowin project sources exist;
- the expected clock and UART pins remain in the constraints.

## Gowin project selection

Open the project matching the carrier and device revision reported by Gowin Programmer.

| Carrier | Device B | Device C |
|---|---|---|
| Tang Mega 138K Dock | `victory_v_mega_138k_b.gprj` | `victory_v_mega_138k_c.gprj` |
| Tang Console 138K | `victory_v_console_138k_b.gprj` | `victory_v_console_138k_c.gprj` |

The projects use `GW5AST-LV138PG484AC1/I0`. Check the actual device before programming.

## Pins used by the first image

### Tang Mega 138K Dock

| Signal | Pin |
|---|---|
| 50 MHz clock | `V22` |
| UART TX | `U15` |
| UART RX | `V14` |
| user key | `F4` |
| onboard LED | `V13` |

The V13 LED is active low. It lights after all three mailbox markers have arrived.

### Tang Console 138K

| Signal | Pin |
|---|---|
| 50 MHz clock | `V22` |
| UART TX | `U15` |
| UART RX | `V14` |
| reset switch `s0` | `AB13` |
| PMOD status LEDs | `D21 E21 D22 E22 F20 F19 W20 W19` |

Console LED bits are:

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

1. Open the matching `.gprj` file.
2. Confirm `top` is the top module.
3. Run synthesis and save the utilization report.
4. Run place-and-route and save the timing report.
5. Check the 50 MHz clock constraint.
6. Program SRAM first. Leave flash alone until reset and UART are repeatable.
7. Open the USB UART at 115200 8N1.
8. Reset the board and record the three lines and LED state.
9. Repeat the reset several times.

A clean synthesis without the three UART lines is not a completed bring-up.

## Resource gate

Before adding DDR3, keep these numbers:

```text
LUT4
FF
BSRAM
DSP
Fmax
worst setup path
```

The planning gate for the plain cluster is:

```text
<= 50% LUT
<= 35% BSRAM
50 MHz timing passes
```

This leaves room for DDR plumbing, caches, framebuffer scanout, and Linux support. If the cluster misses the gate, shrink P0/E0 before adding more hardware.

## After the three lines

```text
privilege and trap entry
  -> atomics and fences
  -> tagged context save/restore
  -> timer and IPI software tests
  -> independent DDR3 memory test
  -> shared uncached memory
  -> physical caches
  -> no-MMU Linux early console
  -> BusyBox
  -> framebuffer and input
  -> DOOM
```

DDR3 should pass a destructive standalone test before either CPU uses it. Page translation remains later work.
