# DOOM Target

DOOM is a useful end-to-end target because it forces the toolchain, C runtime, files, timer, framebuffer, input, and enough memory to work together.

The first route is:

```text
VV64-P0
CONFIG_MMU=n
VRTU flat protection
initramfs
doomgeneric
```

E0 is not required for the first frame. VV32 remains the monitor and control core.

## Gates

1. reproducible Gowin bitstream and three `VTRY ready` lines;
2. compiler and linker;
3. privilege and traps;
4. timer and input;
5. DDR3;
6. no-MMU early console;
7. BusyBox/initramfs;
8. framebuffer;
9. doomgeneric.

The archived Euclid experiment is not part of this path or the default FPGA image.
