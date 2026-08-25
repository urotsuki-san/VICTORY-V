# Architecture Research Notes

Reviewed on 2026-08-26. These sources informed the draft; they are not dependencies and do not prove that VICTORY-V implements the cited work.

## Linux without an MMU

- Linux no-MMU memory mapping documentation: <https://www.kernel.org/doc/html/latest/admin-guide/mm/nommu-mmap.html>
- Linux executable-format configuration: <https://github.com/torvalds/linux/blob/master/fs/Kconfig.binfmt>

The normal ELF loader depends on `MMU`. FDPIC and FLAT are the relevant routes for a new no-MMU architecture port. This is why `VV64-L0/flat` has its own ABI and does not promise conventional paged userspace.

## Capability systems

- CHERI ISAv8: <https://www.cl.cam.ac.uk/techreports/UCAM-CL-TR-951.html>
- CHERIoT 1.0 release: <https://cheriot.org/sail/specification/release/2025/11/03/cheriot-1.0.html>
- CHERIoT sealed pointer types: <https://cheriot.org/sealing/compiler/2025/01/30/introducing-sealed-types.html>

The useful lessons are architectural tags, monotonic bounds and permissions, sealed authority, tagged context, and hardware/software co-design. The `VV64-A0` draft keeps these broad lessons but uses a protected Capability Directory for the first FPGA implementation and retains Secret Tags and Victory Regions as family rules.

## Transient execution

- Cambridge report on transient-execution mitigation for CHERI: <https://www.cl.cam.ac.uk/techreports/UCAM-CL-TR-1001.html>

Capabilities do not automatically solve speculative leakage. The first VICTORY-V cores therefore remain non-speculative. A future performance core must define what state speculation may touch before it can claim conformance.

## Control-flow protection

- Ratified RISC-V CFI specification: <https://docs.riscv.org/reference/isa/unpriv/unpriv-cfi.html>

Landing pads and shadow stacks are useful reference points. `VV64-A0` instead binds indirect entry and return to executable capabilities, sealed gates, and protected return tokens.

## Executable ISA semantics

- Sail ISA language: <https://github.com/rems-project/sail>

The Python model is readable, but it should not remain the only authority as the ISA grows. A Sail model is planned before the `VV64-A0` encoding freezes, with generated tests shared by the readable model, fast emulator, and RTL.

## Tang Console support

- LiteX Tang Console target: <https://github.com/litex-hub/litex-boards/blob/master/litex_boards/targets/sipeed_tang_console.py>

The board and DDR work are useful. Reusing them does not make VICTORY-V a RISC-V wrapper. The CPU remains a native VICTORY-V implementation.

## Decisions from the review

- Keep no-MMU as a first-class 64-bit mode.
- Boot flat Linux before adding `V39`.
- Treat translation as an additional denial layer, never a source of new authority.
- Add tagged context save/restore before claiming multitasking.
- Use generation-checked directory references to reject stale authority.
- Add sealed calls and protected returns instead of relying only on software conventions.
- Keep Victory Regions bounded and architectural.
- Do not use a foreign CPU as a shortcut to the Linux milestone.
