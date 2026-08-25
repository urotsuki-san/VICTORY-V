# Threat Model

## Scope

The implemented subject is `VV32-A0`. `VV64-A0`, its Capability Directory, and both Linux profiles are design targets. This file separates intended rules from evidence already present in the repository.

## Protected state

VICTORY-V is intended to protect:

- memory objects reached through bounded capabilities;
- root authority after `VLOCK`;
- secret-tagged values from direct branch and address flow;
- memory from partial Victory Region updates;
- future tagged context state;
- domain boundaries in flat and paged VV64 systems.

## Software attacker

For A0, assume untrusted or defective software can execute arbitrary legal instructions after boot setup. It cannot directly edit hidden metadata, bypass the core's memory interface, replace the bitstream, or physically probe the FPGA.

It may try to forge a capability, exceed bounds, leak a secret, create a root after `VLOCK`, exhaust a region, leave a partial update, reuse a stale VV64 generation, use page tables to add authority, or corrupt a call/return target.

## Required behavior

- Integer operations clear capability validity.
- Derived capabilities do not widen authority.
- A secret controlling a branch, target, address, or public store fails.
- Region stores remain hidden until `VIC`; abort discards them and reports a cause.
- `VLOCK` is monotonic until reset.
- VV64 context memory preserves tags instead of encoding authority as ordinary bytes.
- VV64 page permissions are intersected with capability and domain rights.
- A flat VV64 process cannot gain another domain by guessing a physical address.

## Not covered yet

The repository does not establish protection against physical or environmental side channels; malicious synthesis, programming, or debug tools; probing, readback, glitching, radiation, or fault injection; ordinary MMIO rollback; bypass DMA; power loss during commit; denial of service; bugs holding legitimate broad authority; complete temporal safety; future speculative leakage; multicore races; or cryptographic correctness merely because a tag exists.

## Claims

A unit test supports a narrow statement about the case it covers. It does not establish complete memory safety, constant-time execution, hard real-time behavior, Linux readiness, or superiority over another ISA. Broader claims need reproducible model, RTL, and FPGA evidence and independent review.
