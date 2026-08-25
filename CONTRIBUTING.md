# Contributing

VICTORY-V is still small enough that an architecture change can be reviewed end to end. Please keep it that way.

A change to `VV32-A0` should update the JSON manifest, Python definition, documentation, tests, and RTL declaration together when they are affected. A change to the family or `VV64-A0` should update `isa/victory-v-family.json`, `src/victory_v/family.py`, and the relevant design document.

Before sending code, run:

```bash
make test
make examples
make family-check
python tools/check_isa_sync.py
make rtl-test
```

For hardware-visible behavior, include a test that fails before the fix. For a security or performance claim, include the smallest reproducible measurement that supports the exact wording.

Large rewrites that mix ISA, prose, build-system, and RTL changes are hard to review. Separate them unless the pieces genuinely cannot stand alone.
