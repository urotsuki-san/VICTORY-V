# Threat Model

## Status

This is a design threat model for a research alpha. It documents intended boundaries; it is not evidence that the implementation meets them.

## Assets

VICTORY-V is intended to protect:

- memory objects reachable only through bounded capabilities;
- secret-derived register values from obvious control-flow and address-flow leakage;
- data-memory state from partial writes when a bounded operation fails;
- root authority after boot-time capability construction is locked;
- interrupt responsiveness from unbounded software regions.

## Attacker model

A0 considers untrusted or defective software that can execute arbitrary VV32-A0 instructions after initial boot setup but cannot:

- physically probe or modify the FPGA;
- replace the bitstream, clock, or reset network;
- directly modify capability metadata outside the defined ISA;
- bypass the core's data-memory interface;
- violate electrical timing or inject faults.

The attacker may attempt out-of-bounds access, permission escalation, capability forgery through integer arithmetic, secret-dependent branches, secret-dependent pointers, nested regions, quota exhaustion, and failure during a multi-write update.

## Intended protections

### Capability integrity

Integer operations clear capability validity. Derived capability operations may narrow authority but must not expand it. All A0 data access is capability mediated.

### Secret-flow restrictions

The core rejects secret-tagged branch conditions and addresses. A secret store requires a secret destination capability. Explicit declassification requires `D` authority.

### Failure containment

Victory Region stores are held internally until `VIC`. Documented aborts discard them and transfer to a fixed failure path.

### Root lock

After `VLOCK`, `CROOT` cannot create new root authority until reset.

## Explicit non-goals and unresolved risks

A0 does **not** currently claim protection against:

- power, electromagnetic, acoustic, thermal, or timing side channels;
- malicious or compromised synthesis/place-and-route tools;
- FPGA configuration readback, physical probing, voltage/clock glitching, radiation, or fault injection;
- rollback of MMIO or external devices;
- DMA masters that bypass the VICTORY-V capability checks;
- speculative execution in a future implementation that departs from the A0 core;
- control-flow integrity for indirect calls and returns;
- capability persistence or secure task switching;
- multi-core races or memory consistency beyond one core;
- power loss during a commit;
- denial of service;
- bugs in software that holds legitimate broad authority;
- cryptographic correctness merely because secret tags are present.

## Security claims policy

The repository may accurately say that a covered test demonstrates a specific modeled behavior. It may not claim broad memory safety, constant-time execution, real-time guarantees, or superiority over another ISA without reproducible measurements and independent review.
