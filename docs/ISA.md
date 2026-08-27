# VV32-A0 Instruction Set

## 1. Encoding

Every instruction is one little-endian 32-bit word. The primary opcode occupies bits `[31:26]`.

### NONE

```text
31          26 25                           0
+--------------+------------------------------+
| opcode (6)   | zero / reserved (26)         |
+--------------+------------------------------+
```

### R

```text
31       26 25   21 20   16 15   11 10       0
+----------+-------+-------+-------+------------+
| opcode   | rd    | rs1   | rs2   | aux (11)   |
+----------+-------+-------+-------+------------+
```

### I

```text
31       26 25   21 20   16 15               0
+----------+-------+-------+--------------------+
| opcode   | rd    | rs1   | immediate (16)     |
+----------+-------+-------+--------------------+
```

For store instructions, `rd` names the source data register. `CSRW` also uses the `rs1` field as its source.

### B

```text
31       26 25   21 20                         0
+----------+-------+-----------------------------+
| opcode   | rs1   | signed word offset (21)     |
+----------+-------+-----------------------------+
```

The target is `PC + 4 + sign_extend(offset) × 4`. Opcode `0x3d` uses the `rs1` field for a prepared-contract token.

### J

```text
31       26 25   21 20                         0
+----------+-------+-----------------------------+
| opcode   | rd    | signed word offset (21)     |
+----------+-------+-----------------------------+
```

### Inline VTRY

```text
31       26 25   21 20      13 12              0
+----------+-------+----------+-------------------+
| opcode   | stores| budget   | signed offset (13)|
+----------+-------+----------+-------------------+
```

The failure target is PC-relative in words. Store quota is `1..31`; instruction budget is `1..255`. An implementation may support fewer stores and must reject an unsupported request rather than truncate it.

## 2. Registers and immediates

- `r0` is hardwired to zero.
- `r31` is the provisional link register.
- `rN`, `vN`, `cN`, and `sN` are aliases for the same register index.
- Signed immediates use two's-complement sign extension unless an instruction explicitly states zero extension.
- Branches and jumps use signed word offsets relative to the following instruction.

## 3. Integer and control instructions

| Opcode | Instruction | Form | Semantics |
|---:|---|---|---|
| `0x00` | `NOP` | NONE | no effect |
| `0x01` | `MOV rd, rs` | R | copy value and all metadata |
| `0x02` | `MOVI rd, imm` | I | sign-extend `imm16` |
| `0x03` | `LUI rd, imm` | I | `imm16 << 16` |
| `0x04` | `ADD rd, a, b` | R | low 32 bits of addition |
| `0x05` | `ADDI rd, a, imm` | I | addition with signed immediate |
| `0x06` | `SUB rd, a, b` | R | low 32 bits of subtraction |
| `0x07` | `MUL rd, a, b` | R | low 32 bits of multiplication |
| `0x08` | `AND rd, a, b` | R | bitwise AND |
| `0x09` | `ANDI rd, a, imm` | I | zero-extended immediate AND |
| `0x0a` | `OR rd, a, b` | R | bitwise OR |
| `0x0b` | `ORI rd, a, imm` | I | zero-extended immediate OR |
| `0x0c` | `XOR rd, a, b` | R | bitwise XOR |
| `0x0d` | `XORI rd, a, imm` | I | zero-extended immediate XOR |
| `0x0e` | `SHL rd, a, b` | R | logical left by `b[4:0]` |
| `0x0f` | `SHR rd, a, b` | R | logical right by `b[4:0]` |
| `0x10` | `SAR rd, a, b` | R | arithmetic right by `b[4:0]` |
| `0x11` | `CMPEQ rd, a, b` | R | write `1` when equal, else `0` |
| `0x12` | `CMPLT rd, a, b` | R | signed less-than |
| `0x13` | `CMPULT rd, a, b` | R | unsigned less-than |
| `0x14` | `BRZ rs, target` | B | branch when zero; secret condition prohibited |
| `0x15` | `BRNZ rs, target` | B | branch when non-zero; secret condition prohibited |
| `0x16` | `JAL rd, target` | J | write return PC and jump |
| `0x17` | `JALR rd, rs, imm` | I | indirect jump; secret target prohibited |
| `0x18` | `HALT` | NONE | stop; prohibited inside an active Region |
| `0x19` | `TRAP code` | I | explicit trap or Region abort |
| `0x1a` | `CSRR rd, csr` | I | read CSR |
| `0x1b` | `CSRW rs, csr` | I | write permitted CSR; prohibited in a Region |
| `0x1c` | `EI` | NONE | enable external interrupts |
| `0x1d` | `DI` | NONE | disable external interrupts |
| `0x1e` | `VRET` | NONE | return to `VEPC` and enable interrupts |

Integer-producing operations clear destination capability and contract-token metadata, and propagate operand secret tags.

## 4. Capability and memory instructions

| Opcode | Instruction | Semantics |
|---:|---|---|
| `0x20` | `CROOT cd, rbase, rlen, perms` | create root capability before `VLOCK`; permission mask is `aux[4:0]` |
| `0x21` | `CBOUNDS cd, cs, rlen` | set base to source cursor and top to cursor + length, without expansion |
| `0x22` | `CPERM cd, cs, rmask` | permissions become `source & mask` |
| `0x23` | `CINC cd, cs, roff` | move cursor by signed 32-bit offset within bounds |
| `0x24` | `CGETTAG rd, cs` | write capability-valid bit |
| `0x25` | `CGETPERM rd, cs` | write permission mask or zero |
| `0x26` | `CLDB rd, cs, off` | signed byte load |
| `0x27` | `CLDBU rd, cs, off` | unsigned byte load |
| `0x28` | `CLDH rd, cs, off` | signed aligned halfword load |
| `0x29` | `CLDHU rd, cs, off` | unsigned aligned halfword load |
| `0x2a` | `CLDW rd, cs, off` | aligned word load |
| `0x2b` | `CSTB rs, cd, off` | byte store |
| `0x2c` | `CSTH rs, cd, off` | aligned halfword store |
| `0x2d` | `CSTW rs, cd, off` | aligned word store |
| `0x2e` | `VDECLASS rd, rs, cAuth` | clear secret tag when `cAuth` has `D` |
| `0x2f` | `VLOCK` | permanently disable `CROOT` until reset |

Capability permission text accepted by the assembler is a combination of `r`, `w`, `x`, `s`, and `d`, for example `rws` or `rwd`.

## 5. Victory instructions

| Opcode | Instruction | Semantics |
|---:|---|---|
| `0x30` | `VTRY fail, stores, budget` (`VTRY.I`) | enter a Region with an inline store/instruction contract |
| `0x31` | `VCHK rs, error` | abort with `error` when `rs == 0`; secret condition prohibited |
| `0x32` | `VIC` | preflight the buffered write set, publish it, and close the Region |
| `0x33` | `VABT error` | discard the write set and branch to the failure target |
| `0x34` | `VERR rd` | read the last Region error |
| `0x35` | `WFI` | wait for interrupt; prohibited in a Region |
| `0x3c` | `VPREP cToken, cArena, rSpec` | admit a one-shot prepared VTRY contract |
| `0x3d` | `VTRY cToken, fail` (`VTRY.C`) | consume a prepared token and enter the Region |
| `0x3e` | `VCANCEL cToken` | invalidate an unused token and all of its copies |

`VTRY` is the architectural Region-entry operation. Operand count selects the encoding: `VTRY fail, stores, budget` emits `VTRY.I`, while `VTRY cToken, fail` emits `VTRY.C`. The explicit spelling `VTRY.C cToken, fail` is also accepted. `VPREP` only admits the contract; it never starts architectural work. The Python and RTL opcode symbol for `0x3d` is `VTRYC`.

`VIC` expands to **Victory Integrity Commit**. `VPREP` fails before work starts when a requested footprint exceeds the selected implementation profile. A token is register metadata: `MOV` may copy it, but integer or capability-producing instructions clear it. Consuming or cancelling any live copy makes every copy stale.

### Contract descriptor

`rSpec` is packed as follows:

| Bits | Field | Range |
|---:|---|---:|
| `4:0` | aligned store granules | `1..31` |
| `12:5` | instruction budget | `1..255` |
| `17:13` | distinct register writes | `1..31` |
| `22:18` | derived-capability allocations | `0..31` |
| `23` | fixed release | boolean |
| `24` | secret contract | boolean |
| `31:25` | release-cycle delta | `0..127` |

Fixed release requires a non-zero delta. A secret contract requires fixed release. `cArena` must be a live capability; every contracted load and store must remain inside its bounds. `CBOUNDS` and `CPERM` consume the admitted capability-allocation budget. `CROOT` remains prohibited inside a Region.

## 6. Control/status registers

| Address | CSR | Access | Meaning |
|---:|---|---|---|
| `0x0000` | `VSTATUS` | R/W subset | bit 0 interrupt enable; bit 1 root locked; bit 2 Region active |
| `0x0001` | `VTVEC` | R/W | aligned trap vector |
| `0x0002` | `VEPC` | R/W | saved fault/interrupt PC |
| `0x0003` | `VCAUSE` | R | latest trap cause |
| `0x0004` | `VBADADDR` | R | related address or explicit code |
| `0x0005` | `VCYCLE` | R | low 32-bit cycle counter |
| `0x0006` | `VINSTRET` | R | low 32-bit retired-instruction counter |
| `0x0007` | `VERROR` | R/W | latest Victory Region error |
| `0x0008` | `VREGION_COUNT` | R | buffered store-granule count |
| `0x0009` | `VREGION_LIMIT` | R | active instruction budget |
| `0x000a` | `VCAP_ALLOC` | R | VV64 Capability Directory allocator position; zero on VV32 |
| `0x000b` | `VCONTRACT` | R | live admitted-contract generation, or zero |
| `0x000c` | `VRELEASE` | R | active or pending fixed release cycle |
| `0x000d` | `VREGION_CAPS` | R | capability quota and used count |

## 7. Architectural causes

| Value | Cause |
|---:|---|
| 1 | illegal instruction |
| 2 | instruction alignment |
| 3 | invalid capability tag |
| 4 | capability bounds |
| 5 | capability permission |
| 6 | prohibited secret flow |
| 7 | root creation after `VLOCK` |
| 8 | nested Victory Region |
| 9 | Region store quota |
| 10 | Region instruction budget |
| 11 | explicit trap |
| 12 | missing declassification authority |
| 13 | external interrupt |
| 14 | data alignment |
| 15 | physical memory range |
| 16 | instruction requires no active Region, or requires an active Region |
| 17 | distinct-register quota |
| 18 | fixed-release deadline |
| 19 | accepted interrupt aborted the Region |
| 20 | VRTU miss |
| 21 | VRTU permission |
| 22 | VRTU overlap conflict |
| 23 | stale Capability Directory reference |
| 24 | stale, forged, or missing contract token |
| 25 | contract admission rejected |
| 26 | access escaped the admitted arena |
| 27 | device access attempted in a Region |
| 28 | derived-capability quota |
| 29 | fault after publication began |
| 30 | capability or contract generation wrap |
| 31 | invalid VRTU configuration |

Inside a Region, these values become `VERROR` and cause rollback before publication. Outside a Region, they become `VCAUSE` and transfer to `VTVEC`. Cause 29 is different: publication has already begun, so the core stops rather than reporting a rollback that did not happen.

## 8. Assembler pseudo-instructions

| Pseudo | Expansion |
|---|---|
| `LI rd, value` | `MOVI`, or `LUI` + `ORI` |
| `CLR rd` | `MOVI rd, 0` |
| `JMP target` | `JAL r0, target` |
| `CALL target` | `JAL r31, target` |
| `RET` | `JALR r0, r31, 0` |
| `.WORD value` | emit one raw 32-bit word |

## 9. VRTU and the CPU ISA

VRTU does not consume a VV32/VV64 opcode. It is an implementation unit on the VV64 instruction and data buses.

VRTU faults use the common cause namespace:

| Value | Cause |
|---:|---|
| 20 | no range covers the complete access |
| 21 | matching range lacks the requested permission |
| 22 | more than one range matches |
| 27 | a selected `DEVICE` range was used by an active Region |
| 31 | a descriptor update was malformed, overlapping, widening, or wrapped its generation |

The archived Euclid experiment likewise has no opcode, but unlike VRTU it is not part of the default hardware image.
