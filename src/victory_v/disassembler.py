"""Disassembler for VICTORY-V VV32-A0 binaries."""

from __future__ import annotations

from collections.abc import Iterable

from .isa import CapabilityPermission, Csr, Opcode, decode, sign_extend


def _r(index: int) -> str:
    return f"r{index}"


def _c(index: int) -> str:
    return f"c{index}"


def _permission(mask: int) -> str:
    letters = ""
    for bit, letter in (
        (CapabilityPermission.READ, "r"),
        (CapabilityPermission.WRITE, "w"),
        (CapabilityPermission.EXECUTE, "x"),
        (CapabilityPermission.SECRET, "s"),
        (CapabilityPermission.DECLASSIFY, "d"),
    ):
        if mask & int(bit):
            letters += letter
    return letters or "none"


def _csr_name(value: int) -> str:
    try:
        return Csr(value).name.lower()
    except ValueError:
        return f"0x{value:04x}"


def disassemble_word(word: int, *, pc: int = 0) -> str:
    try:
        insn = decode(word)
    except ValueError:
        return f".word 0x{word & 0xFFFF_FFFF:08x}"
    op = insn.opcode

    if op in {Opcode.NOP, Opcode.HALT, Opcode.EI, Opcode.DI, Opcode.VRET, Opcode.VLOCK, Opcode.VIC, Opcode.WFI}:
        return op.name.lower()
    if op == Opcode.MOV:
        return f"mov {_r(insn.rd)}, {_r(insn.rs1)}"
    if op in {Opcode.MOVI, Opcode.LUI}:
        imm = sign_extend(insn.imm16, 16) if op == Opcode.MOVI else insn.imm16
        return f"{op.name.lower()} {_r(insn.rd)}, {imm}"
    if op in {
        Opcode.ADD,
        Opcode.SUB,
        Opcode.MUL,
        Opcode.AND,
        Opcode.OR,
        Opcode.XOR,
        Opcode.SHL,
        Opcode.SHR,
        Opcode.SAR,
        Opcode.CMPEQ,
        Opcode.CMPLT,
        Opcode.CMPULT,
    }:
        return f"{op.name.lower()} {_r(insn.rd)}, {_r(insn.rs1)}, {_r(insn.rs2)}"
    if op in {Opcode.ADDI, Opcode.ANDI, Opcode.ORI, Opcode.XORI}:
        imm = sign_extend(insn.imm16, 16) if op == Opcode.ADDI else insn.imm16
        return f"{op.name.lower()} {_r(insn.rd)}, {_r(insn.rs1)}, {imm}"
    if op in {Opcode.BRZ, Opcode.BRNZ}:
        target = (pc + 4 + insn.off21 * 4) & 0xFFFF_FFFF
        return f"{op.name.lower()} {_r(insn.rs1)}, 0x{target:08x}"
    if op == Opcode.JAL:
        target = (pc + 4 + insn.off21 * 4) & 0xFFFF_FFFF
        return f"jal {_r(insn.rd)}, 0x{target:08x}"
    if op == Opcode.JALR:
        return f"jalr {_r(insn.rd)}, {_r(insn.rs1)}, {sign_extend(insn.imm16, 16)}"
    if op == Opcode.TRAP:
        return f"trap 0x{insn.imm16:04x}"
    if op == Opcode.CSRR:
        return f"csrr {_r(insn.rd)}, {_csr_name(insn.imm16)}"
    if op == Opcode.CSRW:
        return f"csrw {_r(insn.rs1)}, {_csr_name(insn.imm16)}"
    if op == Opcode.CROOT:
        return f"croot {_c(insn.rd)}, {_r(insn.rs1)}, {_r(insn.rs2)}, {_permission(insn.aux & 0x1f)}"
    if op in {Opcode.CBOUNDS, Opcode.CPERM, Opcode.CINC}:
        return f"{op.name.lower()} {_c(insn.rd)}, {_c(insn.rs1)}, {_r(insn.rs2)}"
    if op in {Opcode.CGETTAG, Opcode.CGETPERM}:
        return f"{op.name.lower()} {_r(insn.rd)}, {_c(insn.rs1)}"
    if op in {Opcode.CLDB, Opcode.CLDBU, Opcode.CLDH, Opcode.CLDHU, Opcode.CLDW}:
        return f"{op.name.lower()} {_r(insn.rd)}, {_c(insn.rs1)}, {sign_extend(insn.imm16, 16)}"
    if op in {Opcode.CSTB, Opcode.CSTH, Opcode.CSTW}:
        return f"{op.name.lower()} {_r(insn.rd)}, {_c(insn.rs1)}, {sign_extend(insn.imm16, 16)}"
    if op == Opcode.VDECLASS:
        return f"vdeclass {_r(insn.rd)}, {_r(insn.rs1)}, {_c(insn.rs2)}"
    if op == Opcode.VPREP:
        return f"vprep {_c(insn.rd)}, {_c(insn.rs1)}, {_r(insn.rs2)}"
    if op == Opcode.VTRYC:
        target = (pc + 4 + insn.off21 * 4) & 0xFFFF_FFFF
        return f"vtry {_c(insn.rs1)}, 0x{target:08x}"
    if op == Opcode.VCANCEL:
        return f"vcancel {_c(insn.rs1)}"
    if op == Opcode.VTRY:
        target = (pc + 4 + insn.off13 * 4) & 0xFFFF_FFFF
        return f"vtry 0x{target:08x}, {insn.stores}, {insn.budget}"
    if op == Opcode.VCHK:
        return f"vchk {_r(insn.rs1)}, 0x{insn.imm16:04x}"
    if op == Opcode.VABT:
        return f"vabt 0x{insn.imm16:04x}"
    if op == Opcode.VERR:
        return f"verr {_r(insn.rd)}"
    return f".word 0x{word & 0xFFFF_FFFF:08x}"


def disassemble(words: Iterable[int], *, base_pc: int = 0) -> list[str]:
    return [disassemble_word(word, pc=base_pc + index * 4) for index, word in enumerate(words)]
