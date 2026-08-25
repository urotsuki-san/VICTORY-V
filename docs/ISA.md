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

The target is `PC + 4 + sign_extend(offset) × 4`.

### J

```text
31       26 25   21 20                         0
+----------+-------+-----------------------------+
| opcode   | rd    | signed word offset (21)     |
+----------+-------+-----------------------------+
```

### VTRY

```text
31       26 25   21 20      13 12              0
+----------+-------+----------+-------------------+
| opcode   | stores| budget   | signed offset (13)|
+----------+-------+----------+-------------------+
```

The failure target is PC-relative in words. Store quota is `1..31`; instruction budget is `1..255`. An implementation may support fewer stores and must reject an unsupported request rather than silently truncate it.

## 2. Registers and immediates

- `r0` is hardwired to zero.
- `r31` is the provisional link register.
- `rN`, `vN`, `cN`, and `sN` are aliases for the same register index.
- signed immediates use two's-complement sign extension unless an instruction explicitly states zero extension.
- branches and jumps use signed word offsets relative to the following instruction.

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
| `0x18` | `HALT` | NONE | stop; prohibited inside an active region |
| `0x19` | `TRAP code` | I | explicit trap/region abort |
| `0x1a` | `CSRR rd, csr` | I | read CSR |
| `0x1b` | `CSRW rs, csr` | I | write permitted CSR; prohibited in a region |
| `0x1c` | `EI` | NONE | enable external interrupts |
| `0x1d` | `DI` | NONE | disable external interrupts |
| `0x1e` | `VRET` | NONE | return to `VEPC` and enable interrupts |

Integer-producing operations clear destination capability metadata and propagate operand secret tags.

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
| `0x30` | `VTRY fail, stores, budget` | begin bounded region |
| `0x31` | `VCHK rs, error` | abort with `error` when `rs == 0`; secret condition prohibited |
| `0x32` | `VIC` | commit buffered stores and close region |
| `0x33` | `VABT error` | explicitly discard stores and branch to failure target |
| `0x34` | `VERR rd` | read last region error |
| `0x35` | `WFI` | wait for interrupt; prohibited in a region |

`VIC` expands to **Victory Integrity Commit**.

## 6. Control/status registers

| Address | CSR | Access | Meaning |
|---:|---|---|---|
| `0x0000` | `VSTATUS` | R/W subset | bit 0 interrupt enable; bit 1 root locked; bit 2 region active |
| `0x0001` | `VTVEC` | R/W | aligned trap vector |
| `0x0002` | `VEPC` | R/W | saved fault/interrupt PC |
| `0x0003` | `VCAUSE` | R | latest trap cause |
| `0x0004` | `VBADADDR` | R | related address or explicit code |
| `0x0005` | `VCYCLE` | R | low 32-bit cycle counter |
| `0x0006` | `VINSTRET` | R | low 32-bit retired-instruction counter |
| `0x0007` | `VERROR` | R/W | latest Victory Region error |
| `0x0008` | `VREGION_COUNT` | R | buffered store count |
| `0x0009` | `VREGION_LIMIT` | R | active instruction budget |

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
| 9 | region store quota |
| 10 | region instruction budget |
| 11 | explicit trap |
| 12 | missing declassification authority |
| 13 | external interrupt |
| 14 | data alignment |
| 15 | physical memory range |
| 16 | instruction requires no active region, or requires an active region |

Inside a region these values become `VERROR` and cause rollback. Outside a region they become `VCAUSE` and transfer to `VTVEC`.

## 8. Assembler pseudo-instructions

| Pseudo | Expansion |
|---|---|
| `LI rd, value` | `MOVI`, or `LUI` + `ORI` |
| `CLR rd` | `MOVI rd, 0` |
| `JMP target` | `JAL r0, target` |
| `CALL target` | `JAL r31, target` |
| `RET` | `JALR r0, r31, 0` |
| `.WORD value` | emit one raw 32-bit word |
