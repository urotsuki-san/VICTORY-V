# A0 FPGA handoff

The checked-in Tang 138K image is:

```text
VV32-A0 + VV64-P0/VRTU-P0 + VV64-E0/VRTU-E0
```

The Euclid accelerator is retired from the default image and kept only under `experiments/euclid/`.

## A0 contract boundary

`VTRY` remains the Region-entry operation.

The direct form carries store and instruction limits in one instruction. The prepared form uses `VPREP` followed by `VTRY cToken, fail`. `VPREP` admits stores, instructions, distinct register writes, derived capabilities, arena bounds, and optional release time; the second `VTRY` consumes that one-shot token and enters the same checkpoint. `VCANCEL` invalidates an admitted token that will not be used.

Region entry checkpoints integer state, capability state, Secret Tags, token metadata, and—on VV64—the Capability Directory and allocator. Abort restores the checkpoint and discards the write set. An accepted interrupt records cause 13 as the trap and cause 19 as the Region failure, then enters the handler from the declared failure edge.

Stores to the same aligned granule merge. `VIC` probes every entry before any write is issued. Device ranges fail with cause 27. Publication begins only when the complete set passes; a late bus fault is cause 29 and stops the core instead of claiming rollback.

Secret contracts require a fixed release cycle. The result or failure record is held until that cycle.

## VRTU boundary

Every VV64 instruction fetch, data request, and commit preflight passes through an exact range unit. The core supplies the logical access size and privilege input. The first image locks two identity ranges at reset:

```text
RAM / boot  0x00000..0x10000  RWXU
MMIO/root   0x10000..0x20000  supervisor RW DEVICE
```

P0 has four descriptor slots and E0 has two. Descriptor and guard generations are 32 bits. Unused slots remain invalid. The unit has no software refill and no page-table walker.

## Checks before Gowin

```bash
make check
```

This covers the model, both `VTRY` encodings, one-shot tokens, arena and device faults, merged write sets, fixed release, manifests, documentation, all four project files, VV32/VV64 cores, Region preemption, VRTU, dual-core, and three-core simulations. The generated ROM is also run through the executable model and checked byte-for-byte against the checked-in RTL.

The remaining steps require Gowin and hardware:

1. select the board and B/C device project;
2. synthesize and record LUT/FF/BSRAM/DSP plus warnings;
3. place and route at 50 MHz;
4. program SRAM;
5. record the three `VTRY ready` UART lines and LEDs;
6. run the boundary, preflight, device, and interrupt tests in [`FPGA_138K_BRINGUP.md`](FPGA_138K_BRINGUP.md).

No hardware result is claimed before those steps.
