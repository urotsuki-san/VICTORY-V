# VV32-A0 RTL

`vv32_core.sv` is the current board-independent `VV32-A0` core. It is a single-issue, in-order, multi-cycle design.

The interfaces cover instruction fetch, 32-bit data transactions with byte strobes, one external interrupt, and basic halt/debug status. Byte and halfword accesses are converted to aligned word transactions.

Implemented in the prototype:

- the current A0 integer and control opcodes;
- capability metadata and Secret Tags per register;
- capability-only data access;
- secret branch, address, and public-store checks;
- `VLOCK`;
- bounded store buffering and forwarding;
- multi-cycle `VIC` commit;
- region abort and secret-register scrub;
- basic traps, CSRs, and interrupts.

Run the self-checking testbench with:

```bash
make rtl-test
```

It commits value `2`, attempts a failed overwrite, checks rollback and `VERROR`, and confirms that root creation stays locked.

Still missing: board integration, tagged spill/fill, differential traces, reviewed synthesis warnings, timing results, and production CDC/reset analysis.

`VV64-A0` will be a separate core that shares the family contract. This file should not be widened until the small VV32 implementation works on its own target.
