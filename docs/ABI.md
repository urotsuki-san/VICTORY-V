# ABI Notes

## VV32-A0

The current ABI is a convention for hand-written assembly and the future compiler port. It is not yet backed by C.

| Registers | Role | Preservation |
|---|---|---|
| `r0` | zero | fixed |
| `r1`–`r4` | arguments; `r1`–`r2` results | caller-saved |
| `r5`–`r12` | temporaries | caller-saved |
| `r13`–`r20` | saved values | callee-saved |
| `r21`–`r28` | temporaries / platform use | caller-saved in A0 |
| `r29` / `c29` | stack cursor capability | callee-owned |
| `r30` / `c30` | optional frame capability | callee-saved |
| `r31` | link register | caller-saved |

A saved capability includes value, bounds, permissions, validity, and secret state. A0 integer stores cannot preserve that metadata, so a general task switch remains unsupported.

The stack grows down and is 16-byte aligned at a public call boundary. `c29` carries `R|W` permission and bounds for the active stack object. A failed Victory Region does not restore the stack pointer; its failure target repairs ordinary register state as needed.

Trap entry records `VEPC`, `VCAUSE`, and `VBADADDR`, disables interrupts, and transfers to `VTVEC`. `VRET` returns.

## VV64-A0 draft

The provisional 64-bit ABI name is `VLP64`:

- `long`, pointers, and integer registers are 64 bits;
- pointer values carry hidden capability metadata;
- ordinary integer stores do not preserve a pointer capability;
- `CLDC` and `CSTC` save and restore tagged pointer state;
- context, signal, and debugger frames have explicit metadata layouts;
- sealed calls and protected return tokens replace integer-only cross-domain returns.

The register convention should stay close to VV32 unless compiler measurements show a clear reason to change it. Keeping argument, saved, stack, frame, and link roles aligned reduces duplicated assembly and keeps the lineage visible.

`VV64-L0/flat` uses FDPIC or FLAT-style loading. Code, data, and stack may have independent capabilities even when their physical segments are not contiguous. `VV64-L0/paged` keeps the same register and capability rules while adding virtual mappings.

The ABI is not frozen until a compiler can build non-trivial C, save a tagged context, and pass the same tests in the model and RTL.
