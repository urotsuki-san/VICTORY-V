# Formal harness

The harness is deliberately small at the A0 stage. It currently proves bounded safety invariants rather than full ISA equivalence:

- `r0` remains zero and untagged;
- external writes from an active Victory Region occur only during `ST_COMMIT`;
- `VLOCK` is monotonic until reset;
- the store-buffer count never exceeds its physical depth;
- the architectural program counter remains word-aligned.

Run with a SymbiYosys installation:

```bash
sby -f formal/vv32_core.sby
```

The next verification gate is a differential proof between the Python executable model and RTL instruction traces. Passing this harness alone is **not** evidence that VV32-A0 is secure or production-ready.
