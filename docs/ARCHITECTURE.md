# VV32-A0 Architecture

## Status

`VV32-A0` is the first executable VICTORY-V architecture and the source of the family. It is small enough for a low-cost FPGA and remains a standalone target after `VV64-A0` begins.

A0 is an alpha contract. Opcode positions are fixed for this release, but incompatible changes remain possible before a stable profile.

When sources disagree, use this order:

1. this document and [`ISA.md`](ISA.md);
2. [`isa/vv32-a0.json`](../isa/vv32-a0.json);
3. the Python model for covered operational details;
4. RTL where a differential or conformance test checks the behavior.

A mismatch is a defect. An implementation does not redefine the ISA silently.

The family relationship is documented in [`ARCHITECTURE_FAMILY.md`](ARCHITECTURE_FAMILY.md).

## Machine

| Property | `VV32-A0` |
|---|---|
| Instruction width | fixed 32 bits |
| Byte order | little-endian |
| Program counter | 32 bits, four-byte aligned |
| Registers | 32 × 32 bits |
| Data address width | 32 bits |
| Register metadata | capability state and one secret bit |
| Execution | single-issue, in order, multi-cycle |
| Speculation | none |
| Memory consistency | one core, program order |
| Translation | none |
| Nested Victory Regions | prohibited |

The prototype has separate instruction and data interfaces. That is a property of the first core, not a permanent family rule.

## Register state

Each register contains:

```text
value[31:0]
capability { valid, base[31:0], top[31:0], permissions[4:0] }
secret
```

`rN`, `vN`, `cN`, and `sN` name the same physical state. The prefix only states intent.

`r0` is always zero, untagged, and public. Writes to it are discarded.

### Metadata propagation

- `MOV` copies value, capability, and secret state.
- Integer-producing instructions clear the destination capability.
- Arithmetic and comparisons propagate secret state from their operands.
- Capability-producing instructions clear the destination secret bit.
- A load through an `S` capability marks the result secret.
- `VDECLASS` is the only A0 instruction that clears a secret tag while preserving a value.

A0 cannot yet spill a capability to memory. Ordinary stores lose authority metadata. This is acceptable for the first bare-metal core and blocks a general task-switch ABI. `VV64-A0` addresses it with tagged context memory; a later VV32 profile may adopt the same mechanism without silently changing A0.

## Capabilities

A valid capability has a tagged cursor and an interval:

```text
base <= cursor < top
```

`top` is exclusive. A one-past cursor may exist but cannot be dereferenced.

| Bit | Name | Meaning |
|---:|---|---|
| `0x01` | `R` | read data |
| `0x02` | `W` | write data |
| `0x04` | `X` | reserved executable authority |
| `0x08` | `S` | data reached through the capability is secret |
| `0x10` | `D` | may execute `VDECLASS` |

Instruction fetch is not capability-checked in A0, so `X` remains reserved.

`CROOT` creates an initial capability before `VLOCK`. After `VLOCK`, root creation fails until reset. There is no CSR to reopen it.

Derived operations only reduce authority:

- `CBOUNDS` chooses a subrange;
- `CPERM` intersects permissions with a mask;
- `CINC` moves the cursor without changing bounds or rights.

Integer arithmetic on a tagged register clears the tag. A numeric address is not a capability.

Every `CLD*` and `CST*` checks tag, permission, bounds, physical range, alignment, and secret-store policy. A0 has no unchecked data load or store.

## Secret flow

The secret bit catches direct control-flow and address-flow mistakes. It is not a complete side-channel proof.

A secret controlling value causes `SECRET_FLOW` for branches, indirect targets, capability changes, memory addresses, `VCHK`, CSR writes, and public stores. Secret arithmetic is allowed and keeps the tag.

`VDECLASS rd, rs, cAuth` requires a valid capability with `D`. It records authority to release a value; it does not prove that the release is wise.

## Victory Regions

A region begins with:

```asm
vtry failure_target, store_quota, instruction_budget
```

Stores enter a bounded buffer and are not sent to external memory. Loads see the newest overlapping buffered bytes. `VIC` emits the stores in program order and closes the region.

A false `VCHK`, explicit `VABT`, capability or secret fault, quota or budget failure, prohibited irreversible instruction, or nested `VTRY` aborts the region. Abort discards stores, records `VERROR`, scrubs secret registers, and jumps to the failure target.

Ordinary registers and non-secret capabilities are not rolled back. The failure target is a recovery boundary, not a full snapshot restore point.

A0 does not define transactional MMIO. A future SoC must reject it inside a region or use a device protocol that participates in commit.

External interrupts are deferred while a region or its commit is active. The encoded instruction budget bounds execution and the store quota bounds commit transactions. A hard wall-clock claim also requires bounded memories.

`VV64-A0` adds `VTRYA`, which aborts on interrupt instead of deferring it. The inherited `VTRY` behavior remains unchanged.

## Traps and CSRs

Outside a region, a fault records `VEPC`, `VCAUSE`, and `VBADADDR`, disables interrupts, and transfers to `VTVEC`.

The host runner stops when `VTVEC` is zero. That is a debugging policy, not a different architectural rule. CSR addresses and causes are listed in [`ISA.md`](ISA.md).

## Timing

A0 avoids caches, dynamic branch prediction, speculation, and out-of-order issue. That reduces hidden state; it does not prove a worst-case execution time.

The current RTL is multi-cycle. Fetch depends on `imem_ready_i`; memory and commit depend on `dmem_ready_i`. A timing profile must bind those interfaces and publish cycle limits before the project claims hard real-time behavior.

## Evidence labels

- **model-covered** — a Python test covers the behavior;
- **RTL-covered** — a self-checking RTL test covers it;
- **formally constrained** — the formal harness contains an invariant;
- **FPGA-observed** — the same binary ran on hardware;
- **externally reviewed** — an independent review exists.

A feature description should not imply a stronger level than the evidence.
