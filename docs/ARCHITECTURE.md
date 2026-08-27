# VV32-A0 Architecture

## Status

`VV32-A0` is the first executable VICTORY-V architecture and the source of the family. It is small enough for a low-cost FPGA and remains a useful target after `VV64-A0` arrives.

A0 is still alpha. Opcode positions are fixed for this revision, not forever.

When sources disagree, use this order:

1. this document and [`ISA.md`](ISA.md);
2. [`isa/vv32-a0.json`](../isa/vv32-a0.json);
3. the Python model for covered operational details;
4. RTL where a differential or conformance test checks the behavior.

A mismatch is a defect. An implementation does not get to redefine the ISA silently.

The family relationship is documented in [`ARCHITECTURE_FAMILY.md`](ARCHITECTURE_FAMILY.md).

## Machine

| Property | `VV32-A0` |
|---|---|
| Instruction width | fixed 32 bits |
| Byte order | little-endian |
| Program counter | 32 bits, four-byte aligned |
| Registers | 32 × 32 bits |
| Data address width | 32 bits |
| Register metadata | capability state, one secret bit, contract token generation |
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
contract_token_generation[31:0]
```

`rN`, `vN`, `cN`, and `sN` name the same physical state. The prefix states intent.

`r0` is always zero, untagged, and public. Writes to it are discarded.

### Metadata propagation

- `MOV` copies value, capability, secret state, and contract-token state.
- Integer-producing instructions clear the destination capability and contract-token state.
- Arithmetic and comparisons propagate secret state from their operands.
- Capability-producing instructions clear the destination secret bit and contract-token state.
- A load through an `S` capability marks the result secret.
- `VDECLASS` is the only A0 instruction that clears a secret tag while preserving a value.

A0 cannot yet spill a capability to memory. Ordinary stores lose authority metadata. That is sufficient for the first bare-metal core, but not for a general task-switch ABI. `VV64-A0` is intended to gain tagged context memory first; a later VV32 profile may use the same format without silently changing A0.

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

`VTRY` is the architectural entry into a Victory Region. A0 exposes two encodings for it.

The direct form carries a compact contract in the instruction itself:

```asm
vtry   failure_target, stores, instruction_budget
```

It is the shortest path for small jobs and remains a first-class part of the ISA.

The prepared form separates admission from entry:

```asm
vprep  cToken, cArena, rSpec
vtry   cToken, failure_target
```

`VPREP` checks the requested store granules, instruction budget, distinct register writes, derived-capability allocations, arena, and optional release cycle before work begins. It does not enter the Region. The second `VTRY` consumes the token and reaches the same checkpoint as the direct form. The two machine encodings are named `VTRY.I` and `VTRY.C`; the model and RTL call the prepared opcode `VTRYC`.

A copied token does not duplicate authority. Consuming or cancelling one copy makes every copy stale. `VCANCEL` exists for work that was admitted but never started.

Both entry forms snapshot integer values, capability metadata, secret metadata, contract-token metadata, and the failure path. VV64 also snapshots its Capability Directory and allocator. `CBOUNDS` and `CPERM` may derive capabilities inside a prepared Region while the admitted allocation quota remains. `CROOT` is prohibited inside any Region.

Prepared work is also arena-bound. Every contracted load and store must stay inside `cArena`. Requests that do not fit the selected P0/E0 profile fail at `VPREP`; they do not wait until the Region is half finished.

Stores merge by aligned memory granule. Repeated byte, halfword, word, or doubleword writes to one granule consume one write-set entry, and loads see the newest buffered bytes. Device ranges are rejected while a Region is active.

A false `VCHK`, explicit `VABT`, capability or secret fault, arena escape, quota or budget failure, prohibited irreversible instruction, nested entry, or accepted interrupt aborts the Region. Abort discards the write set and restores the entry snapshot before control reaches the failure path. `VERROR`, the failure PC, counters, and an accepted interrupt are the named failure record and are not rolled back.

`VIC` has two phases. `ST_PREFLIGHT` probes every buffered entry through the normal protection path without writing memory. Publication starts only after all entries pass address, permission, range, and device checks. Once publication starts, interrupts wait for the short commit sequence. A bus fault after that point is `COMMIT_PROTOCOL`; the core stops instead of pretending an already visible write disappeared.

A fixed-release contract holds success or failure until the admitted cycle. Secret contracts require fixed release. This closes the architectural early-finish signal; it says nothing about power, electromagnetic leakage, or contention outside the core.

## Traps and CSRs

Outside a Region, a fault records `VEPC`, `VCAUSE`, and `VBADADDR`, disables interrupts, and transfers to `VTVEC`.

The host runner stops when `VTVEC` is zero. That is a debugging policy, not a different architectural rule. CSR addresses and causes are listed in [`ISA.md`](ISA.md).

## Timing

A0 avoids caches, dynamic branch prediction, speculation, and out-of-order issue. That reduces hidden state; it does not prove a worst-case execution time.

The current RTL is multi-cycle. Fetch depends on `imem_ready_i`; memory and commit depend on `dmem_ready_i`. A timing profile must bind those interfaces and publish cycle limits before the project claims hard real-time behavior.

## Current Tang 138K system

VV32 coexists with `VV64-P0` and `VV64-E0` in the Tang 138K source image. Both VV64 profiles pass instruction and data traffic through VRTU. This does not change the VV32 instruction encoding.

VV32 remains the control and monitor CPU, and the natural budget root. The checked-in ROM runs direct `VTRY` commit, prepared `VTRY` commit, and rollback before a core announces itself. The VV64 ROMs also expect Region access to the device window to fail. The retired Euclid block is isolated under `experiments/euclid/` and is not part of the board image.

VRTU is a VV64 implementation component; it does not silently redefine `VV32-A0`.

## Evidence labels

- **model-covered** — a Python test covers the behavior;
- **RTL-covered** — a self-checking RTL test covers it;
- **formally constrained** — the formal harness contains an invariant;
- **FPGA-observed** — the same binary ran on hardware;
- **externally reviewed** — an independent review exists.

A feature description should not imply a stronger level than the evidence.
