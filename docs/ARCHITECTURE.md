# VV32-A0 Architecture

## 1. Status and scope

`VV32-A0` is the first executable VICTORY-V architecture contract. It is intentionally small enough to implement as a board-independent FPGA soft core and strict enough to test the ideas that distinguish the project.

A0 is not a stable production ISA. Instruction encodings are fixed for this alpha release, but incompatible changes remain possible before the first stable profile.

The normative sources are:

1. this document and [`ISA.md`](ISA.md);
2. [`isa/vv32-a0.json`](../isa/vv32-a0.json);
3. the Python executable model for operational edge cases;
4. the RTL only after a behavior is covered by a differential or conformance test.

When these disagree, the discrepancy is a defect. No implementation may silently redefine the architecture.

## 2. Design objective

VICTORY-V does not attempt to cover servers, desktops, Linux application processors, or every embedded workload. A0 tests a narrower architecture:

- every data-memory access is capability checked;
- secret-derived values cannot choose a branch or address;
- a bounded region can stage memory writes and either commit or discard them;
- interrupt deferral is bounded by an encoded instruction budget;
- execution is in order and non-speculative;
- success is explicit rather than inferred from a lack of exceptions.

## 3. Base machine

| Property | VV32-A0 |
|---|---|
| Instruction width | fixed 32 bit |
| Byte order | little-endian |
| Program counter | 32 bit, four-byte aligned |
| Integer registers | 32 × 32 bit |
| Capability metadata | valid, base, exclusive top, five permission bits per register |
| Secret metadata | one secret bit per register |
| Data-address width | 32 bit |
| Execution | single-issue, in order, multi-cycle |
| Speculation | none in the A0 RTL |
| Memory consistency | one core, program order |
| Nested Victory Regions | prohibited |

The instruction and data interfaces are separate in the prototype RTL. This is an implementation choice for the first FPGA target, not a requirement that future profiles remain Harvard-only.

## 4. Register state

Each architectural register has three associated components:

```text
value[31:0]
capability { valid, base[31:0], top[31:0], permissions[4:0] }
secret
```

Assembly names `rN`, `vN`, `cN`, and `sN` refer to the same numbered register. The prefix communicates intent; it does not select another physical bank.

### 4.1 Zero register

`r0` is always zero. Its capability is always invalid and its secret bit is always clear. Writes to it are discarded.

### 4.2 Metadata propagation

- `MOV` copies value, capability metadata, and secret metadata.
- integer-producing instructions clear the destination capability tag;
- arithmetic and comparisons propagate secret metadata from their operands;
- capability-producing instructions clear the destination secret bit;
- loads through a `SECRET` capability mark the result secret;
- `VDECLASS` is the only A0 instruction that intentionally clears a secret tag while preserving a value.

A0 does not yet provide capability load/store instructions. Capabilities therefore cannot be spilled to ordinary memory without losing authority metadata. This is acceptable for the bare-metal FPGA milestone but is a blocker for a complete multitasking ABI and is tracked in the roadmap.

## 5. Capability model

A capability is valid only when its tag bit is set. Its range is:

```text
base <= cursor < top
```

The cursor is the ordinary register value. `top` is exclusive. A cursor may temporarily equal `top` as a one-past pointer, but an access at that cursor fails.

### 5.1 Permissions

| Bit | Name | Meaning |
|---:|---|---|
| `0x01` | `R` | data read |
| `0x02` | `W` | data write |
| `0x04` | `X` | reserved for executable capabilities |
| `0x08` | `S` | memory reached through this capability is secret |
| `0x10` | `D` | authority to execute `VDECLASS` |

`X` is reserved in A0. Instruction fetch is not capability mediated yet.

### 5.2 Authority creation and reduction

`CROOT` creates a root capability from an integer base, integer length, and immediate permission mask. It is available only before `VLOCK`.

`VLOCK` is monotonic until reset. After it executes, all later `CROOT` instructions fail with `ROOT_LOCKED`. No CSR can clear the lock.

Derived capabilities can only reduce authority:

- `CBOUNDS` sets a new base at the source cursor and a new top at cursor + length; the result must remain within the source bounds;
- `CPERM` performs a bitwise AND between the source permissions and a mask;
- `CINC` changes the cursor but not bounds or permissions.

Integer arithmetic on a capability register clears its capability tag. This prevents ordinary arithmetic from forging a tagged pointer.

### 5.3 Access checks

Every `CLD*` and `CST*` operation checks, in effect:

1. the capability register itself is not secret-tagged;
2. its capability tag is valid;
3. the required `R` or `W` permission is present;
4. effective address and access end remain inside `[base, top)`;
5. the physical A0 data-memory range contains the access;
6. halfword and word natural alignment holds;
7. a secret source is not stored through a non-secret capability.

There are no raw A0 data load/store instructions that bypass these checks.

## 6. Secret-flow rules

The A0 secret tag is a small dynamic information-flow mechanism. It is intended to reject obvious secret-dependent control flow and addressing, not to prove complete side-channel resistance.

The following operations fail with `SECRET_FLOW` when their controlling input is secret:

- `BRZ` and `BRNZ` condition registers;
- `JALR` target registers;
- capability cursor changes using a secret offset;
- capability bounds or permission changes using secret operands;
- memory addressing through a secret-tagged capability register;
- `VCHK` on a secret condition;
- CSR writes sourced from a secret value;
- stores of secret data to a capability without `S`.

Arithmetic on secret data is allowed and propagates the secret tag. Fixed execution timing for each arithmetic operation is an implementation goal, but A0 has not yet been measured or formally proven constant-time in FPGA fabric.

### 6.1 Declassification

`VDECLASS rd, rs, cAuth` succeeds only when `cAuth` is a valid capability with `D`. The destination receives the source value as a non-secret integer and no capability metadata.

This is explicit authority, not an assertion that the released value is safe. Software remains responsible for deciding what may be revealed.

## 7. Victory Regions

A Victory Region begins with:

```asm
vtry failure_target, store_quota, instruction_budget
```

The instruction encodes:

- a PC-relative failure target;
- a requested maximum number of stores;
- a maximum number of instructions allowed before the region must finish.

A0 forbids nested regions.

### 7.1 Buffered state

Data-memory stores inside an active region enter a bounded store buffer. They are not emitted to external data memory. Loads observe the newest buffered byte for overlapping addresses, so a region sees its own writes.

`VIC` commits buffered stores in program order and clears the region. In the multi-cycle RTL, this takes one accepted memory transaction per buffered entry.

### 7.2 Abort conditions

A region aborts when any of the following occurs:

- `VCHK` observes zero;
- `VABT` executes;
- a capability, alignment, permission, or secret-flow check fails;
- the store quota is exhausted;
- the instruction budget is exhausted;
- a prohibited irreversible control instruction executes;
- another `VTRY` attempts to nest a region.

Abort behavior is:

1. discard all buffered stores;
2. set `VERROR` to the explicit error or architectural cause;
3. clear the active-region state;
4. scrub all currently secret-tagged registers;
5. branch to the encoded failure target.

### 7.3 What is and is not rolled back

A0 guarantees rollback of buffered **data-memory stores** only. General registers and non-secret capability-register changes are not restored. Secret-tagged registers are scrubbed rather than restored.

Consequently, software must treat the failure target as a recovery boundary and must not assume a transactional register snapshot.

MMIO is not part of the A0 memory model. A future SoC must either reject MMIO from a region or route it through a commit-aware command queue. Ordinary irreversible device writes may not be described as rollback-safe.

### 7.4 Interrupt behavior

External interrupts are deferred while a region is active, including its commit phase. The encoded instruction budget bounds execution before `VIC` or abort; the store quota bounds commit transactions.

The exact wall-clock latency also depends on memory ready signals. A future timing profile must define a bounded memory target before claiming a hard real-time interrupt limit.

## 8. Traps and control/status registers

Outside a Victory Region, architectural faults save:

- faulting instruction PC in `VEPC`;
- cause in `VCAUSE`;
- relevant address or explicit value in `VBADADDR`;
- then clear interrupt enable and transfer to `VTVEC`.

The host-side Python runner stops and marks a fault when `VTVEC` remains zero. This is a debugging policy of the executable tool; the architectural transition remains a transfer to `VTVEC`.

A0 CSRs are listed in [`ISA.md`](ISA.md). Only interrupt enable, trap vector, exception PC, and Victory error have writable behavior. Read-only counters silently ignore writes.

## 9. Timing status

A0 intentionally avoids caches, speculative execution, out-of-order scheduling, and dynamic branch prediction. That reduces hidden state but does not by itself prove timing predictability.

The current RTL is multi-cycle:

- most register instructions complete in one execute state;
- load and non-region store latency depends on `dmem_ready_i`;
- `VIC` latency depends on buffered-store count and `dmem_ready_i`;
- fetch latency depends on `imem_ready_i`.

A later `VV32-T1` timing profile must bind these interfaces to bounded memories and publish maximum-cycle tables before the project claims hard real-time behavior.

## 10. Conformance levels

The project distinguishes:

- **model-covered** — behavior has Python unit tests;
- **RTL-covered** — a self-checking RTL simulation exercises it;
- **formally constrained** — an invariant appears in the formal harness;
- **FPGA-observed** — the same binary has run on the target board;
- **externally reviewed** — independent review exists.

A README feature entry must not imply a stronger level than the available evidence.
