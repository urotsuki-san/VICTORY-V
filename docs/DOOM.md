# DOOM Target

## Goal

The public demo is simple to describe:

```text
VICTORY-V 1P1E + VV32
Tang 138K
no-MMU Linux
BusyBox
DOOM over HDMI
```

P0 runs the game. E0 remains available to Linux for background work. VV32 handles monitoring and the narrow control path.

This is the last milestone, not the first hardware test.

## Port choice

The first port should use `doomgeneric`. It asks the platform for a small set of services:

- draw a frame;
- read keys;
- sleep;
- return a millisecond counter;
- perform basic initialization.

That keeps the game separate from the board drivers. The same build can run in the emulator before it reaches the FPGA.

Do not add sound to the first target. Video and input are enough to prove the system.

## Display path

The initial renderer remains 320 × 200. Linux writes a software framebuffer in DDR3. FPGA scanout reads it and scales to an HDMI mode accepted by the display.

```text
doomgeneric XRGB8888 buffer
  -> /dev/fb0 or a small VICTORY framebuffer driver
  -> DDR3
  -> scanout DMA
  -> nearest-neighbour scale
  -> HDMI
```

A double buffer is preferable, but a single buffer with tearing is acceptable for the first boot video.

The scanout block must not depend on the CPU meeting every pixel deadline. DDR burst reads and a line buffer keep video timing separate from game timing.

## Input path

The first usable order is:

1. UART keys;
2. PS/2 keyboard if the carrier exposes it cleanly;
3. USB HID after the basic game works;
4. gamepad mapping later.

VV32 may collect input and forward compact events to Linux through the mailbox device. This gives the control core a useful job without making it part of Linux SMP.

## Filesystem and WAD

The kernel can start from an initramfs. DOOM and its support files may live there initially; SD storage can follow.

The repository must not contain a commercial `DOOM.WAD`. Tests should use a user-supplied WAD, the shareware data where redistribution permits it, or a freely distributable IWAD such as Freedoom.

## Performance work

DOOM does not need an MMU or floating point, but it does need reasonable memory behaviour.

The likely order of useful optimization is:

1. instruction cache on P0;
2. data cache or shared cache;
3. DDR burst access;
4. fast multiply and divide;
5. branch handling;
6. framebuffer write combining;
7. move background work to E0.

A slow first frame is still progress. The first acceptance target is not a fixed frame rate. It is a playable E1M1-class scene with stable input and no memory-protection failures.

## Milestones

```text
D0  doomgeneric runs in the fast VV64 emulator
D1  Linux framebuffer test pattern appears over HDMI
D2  keyboard events reach a user process
D3  doomgeneric starts and draws the title screen
D4  a level loads and accepts movement/fire input
D5  P0 runs DOOM while E0 remains online
D6  VV32 watchdog recovers a deliberately crashed VV64 cluster
```

## Evidence to keep

For the final demo, record:

- VICTORY-V, compiler, kernel, BusyBox, and doomgeneric revisions;
- kernel configuration with `CONFIG_MMU=n`;
- FPGA utilization, Fmax, and DDR test results;
- serial boot log;
- `/proc/cpuinfo` or an equivalent platform report;
- framebuffer mode and measured frame rate;
- WAD source;
- capability and stale-generation negative tests performed before the game starts.
