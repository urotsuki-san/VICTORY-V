# Threat Model

A0 is experimental RTL, not a security certification.

## What the current design enforces

- capability bounds and permissions on data access;
- `VLOCK` for closing root creation;
- complete register/capability rollback on Region abort;
- VV64 Capability Directory and allocator rollback;
- direct `VTRY` and one-shot contract-token admission for prepared `VTRY`;
- stale-copy rejection for consumed or cancelled tokens;
- store, instruction, distinct-register, derived-capability, and arena limits;
- repeated stores merge into a bounded aligned write set;
- device ranges are rejected while a Region is active;
- the complete write set is preflighted before publication;
- a late publication fault is fatal rather than reported as rollback;
- fixed architectural release for contracts marked secret;
- VRTU exact range, logical-size, privilege, and permission checks;
- VRTU overlap and malformed configuration are faults;
- 32-bit descriptor and Capability Directory generations reject wrap.

## What remains outside the boundary

- privilege separation inside the CPU;
- tagged context memory;
- DMA isolation;
- a DDR/shared-memory no-fault commit domain;
- cache, power, electromagnetic, and contention side channels;
- transactional peripheral output beyond rejection;
- debug access control;
- secure boot;
- paged virtual memory.

Fixed release closes the architectural early-completion signal only. It is not a constant-power or constant-contention proof.

VRTU is useful protection for a no-MMU system, but it does not replace the missing privilege, context, DMA, and boot machinery.

The archived Euclid code is outside the shipping image and has no authority over CPU addresses or results.
