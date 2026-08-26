# Tang 138K Bring-up

## Status

The repository now reaches the last useful point before the board is required:

- VV32-A0 and a VV64-A0 FPGA subset are synthesizable SystemVerilog modules;
- both cores fit behind one board-independent SoC top;
- the boot ROM, UART, on-chip RAM, mailbox, reset path, and LED status are wired;
- self-checking simulations cover the VV64 core and the dual-core image;
- Gowin projects are present for Tang Mega 138K and Tang Console 138K, device revisions B and C.

No bitstream or hardware result is claimed. Gowin synthesis, place-and-route, timing closure, programming, and the UART transcript still require the actual tool installation and board.

## First image

```text
50 MHz board clock
        |
        +-- reset synchronizer
        |
        +-- VV32-A0 ---- 64 KiB RAM --+
        |                              |
        +-- VV64-A0 ---- 64 KiB RAM --+-- UART TX
                                       +-- mailboxes
                                       +-- status LEDs
```

The memories are separate on purpose. Shared DDR, caches, arbitration, and coherency would hide basic core failures during first power-on.

VV32 starts at reset and prints its line. VV64 is released after the VV32 mailbox is written, with a timeout as a recovery path. The expected serial output is:

```text
VV32-A0 ready
VV64-A0 ready
```

Default UART settings are 115200 baud, 8 data bits, no parity, one stop bit.

## MMIO page

| Address | Register | Use |
|---:|---|---|
| `0x0001_0000` | UART TX | low byte is transmitted |
| `0x0001_0010` | VV32 mailbox | boot marker `0x32` |
| `0x0001_0018` | VV64 mailbox | boot marker `0x64` |
| `0x0001_0020` | LED register | software status value |
| `0x0001_0028` | status | current hardware status bits |

Both cores create one root capability covering `0x0000_0000` through `0x0001_ffff`, derive a cursor for the MMIO page, call `VLOCK`, print the message, write the mailbox, and halt.

## Simulation

Icarus Verilog is sufficient for the repository tests.

```bash
make fpga-check
make rtl-test-vv64
make rtl-test-dual
```

`fpga-check` also verifies that:

- VV64 did not move any inherited VV32 primary opcode;
- the generated ROM is current;
- all files named by the Gowin projects exist;
- the expected clock and UART pins are present in the constraints.

## Gowin project selection

Open the project that matches both the carrier and the device revision printed on the FPGA or reported by Gowin Programmer.

| Carrier | Device B | Device C |
|---|---|---|
| Tang Mega 138K Dock | `victory_v_mega_138k_b.gprj` | `victory_v_mega_138k_c.gprj` |
| Tang Console 138K | `victory_v_console_138k_b.gprj` | `victory_v_console_138k_c.gprj` |

The projects use the `GW5AST-LV138PG484AC1/I0` part definition. Check the board label before programming; Sipeed has shipped more than one device revision.

## Pins used by the first image

### Tang Mega 138K Dock

| Signal | Pin |
|---|---|
| 50 MHz clock | `V22` |
| UART TX | `U15` |
| UART RX | `V14` |
| user key | `F4` |
| onboard LED | `V13` |

The F4 key is pulled down and is treated as an active-high reset request. The V13 LED is active low and turns on after both boot mailboxes are present.

### Tang Console 138K

| Signal | Pin |
|---|---|
| 50 MHz clock | `V22` |
| UART TX | `U15` |
| UART RX | `V14` |
| reset switch `s0` | `AB13` |
| PMOD status LEDs | `D21 E21 D22 E22 F20 F19 W20 W19` |

The Console image exposes all eight status bits. Bits 0 and 1 are the VV32 and VV64 mailboxes; bits 2 and 3 are halt state; bits 4 and 5 are `VLOCK`; bit 6 reports a core cause; bit 7 follows UART busy.

## First board session

1. Open the matching `.gprj` file in Gowin EDA.
2. Set `top` as the top module if the project does not pick it automatically.
3. Run synthesis and inspect every error and warning.
4. Run place-and-route and confirm the 50 MHz constraint passes.
5. Program SRAM first. Do not write flash until the image behaves correctly.
6. Open the onboard USB UART at 115200 8N1.
7. Reset the design and record the two lines, LED state, tool version, device revision, utilization, timing summary, and bitstream hash.

A synthesis success without the two UART lines is not a completed bring-up.

## After the first two lines

The next hardware work should stay in this order:

```text
timer and interrupt
  -> tagged context storage
  -> privilege transitions
  -> atomics and fences
  -> independent DDR3 memory test
  -> CPU-to-DDR bridge
  -> no-MMU Linux early console
```

DDR3 is not part of the first image. The vendor memory controller should be tested by itself before it is placed behind either CPU. Page translation remains later work.
