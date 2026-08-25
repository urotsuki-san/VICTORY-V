# Contributing

VICTORY-V is in architecture-alpha stage. Small, evidence-backed changes are preferred over broad rewrites.

Before proposing a change:

1. State which A0 invariant or documented behavior changes.
2. Update `isa/vv32-a0.json`, Python definitions, RTL declarations, and ISA documentation together.
3. Add a reference-model test that fails before the change.
4. Add or update an RTL test when hardware-visible behavior changes.
5. Run:

```bash
make test
make examples
python tools/check_isa_sync.py
make rtl-test
```

Security and superiority claims require reproducible evidence. A passing unit test is not sufficient evidence for a broad security claim.
