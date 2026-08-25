# VV32-A0 RTL

`vv32_core.sv` is a board-independent, single-issue, in-order, multi-cycle SystemVerilog implementation of the A0 architecture.

## Interfaces

- instruction request/address/read-data/ready;
- 32-bit data request with byte strobes and ready handshake;
- one level-sensitive external interrupt;
- halt and debug status outputs.

The core expects a word-oriented data bus. Byte and halfword operations are converted to aligned word transactions with write strobes.

## Implemented mechanisms

- all A0 integer/control opcodes;
- per-register capability metadata and secret tags;
- capability-only loads and stores;
- secret branch/address/store restrictions;
- `VLOCK` root creation lock;
- bounded store buffer;
- load forwarding from buffered writes;
- multi-cycle `VIC` commit;
- region abort and secret-register scrub;
- minimal trap/CSR/interrupt state.

## Simulation

```bash
make rtl-test
```

The self-checking testbench creates a capability, commits value `2`, attempts to overwrite it with `99`, forces `VCHK` failure, verifies rollback, checks `VERROR`, and verifies that root creation is locked.

## Known limitations

- no board wrapper, RAM primitive wrapper, PLL, UART, timer, or constraints;
- no capability spill/fill format;
- no differential trace harness yet;
- cycle counters are diagnostic and not yet a normative timing contract;
- MMIO semantics are not defined;
- no production CDC/reset analysis;
- no FPGA synthesis or timing result has been published.
