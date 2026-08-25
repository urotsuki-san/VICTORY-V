# Formal Checks

The current harness checks bounded invariants for the `VV32-A0` RTL:

- `r0` stays zero and untagged;
- a region does not issue an external write before commit;
- `VLOCK` is monotonic until reset;
- the store-buffer count stays inside its physical depth;
- the program counter remains aligned.

Run it with SymbiYosys:

```bash
sby -f formal/vv32_core.sby
```

These assertions are not a full proof of the ISA or a security certificate. The next useful step is generated differential traces between the Python model and RTL. Future `VV64-A0` checks add directory generations, tagged context, translation authority, sealed returns, and `VTRYA`.
