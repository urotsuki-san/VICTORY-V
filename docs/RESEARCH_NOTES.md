# Architecture Research Notes

Reviewed on 2026-08-28. These papers and specifications are design inputs, not performance results for VICTORY-V.

## Linux without an MMU

- Linux no-MMU memory mapping documentation: <https://www.kernel.org/doc/html/latest/admin-guide/mm/nommu-mmap.html>
- Linux executable-format configuration: <https://github.com/torvalds/linux/blob/master/fs/Kconfig.binfmt>

The first Linux route is a real no-MMU profile. FDPIC/FLAT remain the relevant userspace directions until a paged profile exists.

## Capability systems

- CHERI ISAv8: <https://www.cl.cam.ac.uk/techreports/UCAM-CL-TR-951.html>
- CHERIoT 1.0: <https://cheriot.org/sail/specification/release/2025/11/03/cheriot-1.0.html>

VICTORY-V borrows broad lessons—tagged authority, monotonic bounds, protected control flow—but keeps its own ISA, Secret Tags, `VTRY`/`VIC` Regions, and FPGA-oriented Capability Directory.

## Bounded work and prepared VTRY

The direct `VTRY` form is deliberately small. The prepared path adds an admission step so a core can reject work that does not fit its physical contract capacity.

A0 now uses one public entry mnemonic. Three operands select inline `VTRY.I`; two operands select prepared `VTRY.C`. The descriptor still needs a versioned extension path before the ISA is stable.

## Archived Euclid experiment

- MINT, dynamic-precision MSDF arithmetic: <https://arxiv.org/abs/2606.31514>
- D-NOVA, dual-bound similarity search: <https://arxiv.org/abs/2607.17538>
- DICE, statically scheduled CGRA p-graphs: <https://arxiv.org/abs/2605.05496>
- Dynamic control flow for runtime-reconfigurable processors: <https://arxiv.org/abs/2605.21203>
- GEN-Graph, recursive partitioning on heterogeneous PIM tiles: <https://arxiv.org/abs/2604.15361>

Euclid explored a simple question: can an exact decision finish before every arithmetic term is evaluated? The archived model and RTL use partial squared-distance bounds for nearest-neighbour selection. They do not implement the cited accelerators.

The useful pieces were smaller than the original block:

- guarded reuse needs a validity condition;
- early rejection must remain exact;
- scheduling hints may save cycles but must not change the accepted result.

Those ideas now inform VRTU. The Euclid datapath itself is not in the default FPGA image.

## Refinement and ranking references

- Probabilistic denoising hardware: <https://arxiv.org/abs/2510.23972>
- FReDA: <https://arxiv.org/abs/2606.08357>
- Latent Refinement Decoding: <https://arxiv.org/abs/2510.11052>
- MASQ: <https://arxiv.org/abs/2605.23226>
- FPGA hyperdimensional-computing primitives: <https://arxiv.org/abs/2601.20061>
- Ascend-RaBitQ: <https://arxiv.org/abs/2605.16007>
- Constable stable-load elimination: <https://arxiv.org/abs/2406.18786>

These are scheduling and reuse references, not proof that the archived Euclid circuit is fast. Any speed, area, or energy claim has to come from this implementation.

## Executable ISA semantics

- Sail: <https://github.com/rems-project/sail>

A Sail model remains a useful target before the 64-bit ISA freezes. The current executable authority is split between the VV32 Python model, machine-readable declarations, and self-checking RTL tests.

## Tang Console support

- LiteX Tang Console target: <https://github.com/litex-hub/litex-boards/blob/master/litex_boards/targets/sipeed_tang_console.py>

Board and DDR knowledge can be reused without importing another CPU architecture.

## Current decisions

- keep VV32 as a permanent control architecture;
- boot flat/no-MMU VV64 Linux before `V39`;
- keep P0 and E0 on one VV64 ISA;
- keep `VTRY` as the Region entry and treat the prepared path as its extension;
- keep Victory Regions bounded and explicit;
- keep Euclid outside the default FPGA image;
- reuse guarded checks only while generation, bounds, and permissions remain exact;
- do not quote another paper's speedup as a VICTORY-V result.
