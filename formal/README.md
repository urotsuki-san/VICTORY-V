# Formal

The current harness covers a small VV32 subset and a few basic invariants. It does not prove the complete CPU, the prepared `VTRY` path, commit publication, or VRTU.

The next useful properties are:

- an aborted Region emits no store;
- abort restores every architectural register and capability field;
- a prepared token is consumed exactly once;
- preflight failure leaves publication unopened;
- VRTU never returns a physical address on miss, permission failure, or overlap;
- a VRTU guard is usable only with the current descriptor generation;
- VRTU translation cannot add permissions.

Until those properties are in the harness, the RTL tests are evidence for the exercised traces, not a general proof.

The Euclid experiment is outside the formal target.
