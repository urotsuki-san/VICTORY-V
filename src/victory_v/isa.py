"""VICTORY-V VV32-A0 instruction set definitions.

The encoding is intentionally small and fixed-width so the executable model,
assembler, RTL, and documentation can share one unambiguous contract.
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import IntEnum, IntFlag
from typing import Final

WORD_BYTES: Final[int] = 4
REGISTER_COUNT: Final[int] = 32
LINK_REGISTER: Final[int] = 31
DEFAULT_REGION_STORE_DEPTH: Final[int] = 8
DEFAULT_REGION_REGISTER_DEPTH: Final[int] = 31
DEFAULT_REGION_INSTRUCTION_LIMIT: Final[int] = 255


class Format(IntEnum):
    """Internal numeric instruction format identifiers."""

    NONE = 0
    R = 1
    I = 2
    B = 3
    J = 4
    VTRY = 5


FORMAT_NAMES: Final[dict[Format, str]] = {
    Format.NONE: "NONE",
    Format.R: "R",
    Format.I: "I",
    Format.B: "B",
    Format.J: "J",
    Format.VTRY: "VTRY",
}


class Opcode(IntEnum):
    NOP = 0x00
    MOV = 0x01
    MOVI = 0x02
    LUI = 0x03
    ADD = 0x04
    ADDI = 0x05
    SUB = 0x06
    MUL = 0x07
    AND = 0x08
    ANDI = 0x09
    OR = 0x0A
    ORI = 0x0B
    XOR = 0x0C
    XORI = 0x0D
    SHL = 0x0E
    SHR = 0x0F
    SAR = 0x10
    CMPEQ = 0x11
    CMPLT = 0x12
    CMPULT = 0x13
    BRZ = 0x14
    BRNZ = 0x15
    JAL = 0x16
    JALR = 0x17
    HALT = 0x18
    TRAP = 0x19
    CSRR = 0x1A
    CSRW = 0x1B
    EI = 0x1C
    DI = 0x1D
    VRET = 0x1E

    CROOT = 0x20
    CBOUNDS = 0x21
    CPERM = 0x22
    CINC = 0x23
    CGETTAG = 0x24
    CGETPERM = 0x25
    CLDB = 0x26
    CLDBU = 0x27
    CLDH = 0x28
    CLDHU = 0x29
    CLDW = 0x2A
    CSTB = 0x2B
    CSTH = 0x2C
    CSTW = 0x2D
    VDECLASS = 0x2E
    VLOCK = 0x2F

    VTRY = 0x30
    VCHK = 0x31
    VIC = 0x32
    VABT = 0x33
    VERR = 0x34
    WFI = 0x35

    VPREP = 0x3C
    VTRYC = 0x3D
    VCANCEL = 0x3E


class CapabilityPermission(IntFlag):
    READ = 0x01
    WRITE = 0x02
    EXECUTE = 0x04
    SECRET = 0x08
    DECLASSIFY = 0x10


class Csr(IntEnum):
    VSTATUS = 0x0000
    VTVEC = 0x0001
    VEPC = 0x0002
    VCAUSE = 0x0003
    VBADADDR = 0x0004
    VCYCLE = 0x0005
    VINSTRET = 0x0006
    VERROR = 0x0007
    VREGION_COUNT = 0x0008
    VREGION_LIMIT = 0x0009
    VCAP_ALLOC = 0x000A
    VCONTRACT = 0x000B
    VRELEASE = 0x000C
    VREGION_CAPS = 0x000D


class Cause(IntEnum):
    NONE = 0
    ILLEGAL_INSTRUCTION = 1
    INSTRUCTION_ALIGNMENT = 2
    CAPABILITY_TAG = 3
    CAPABILITY_BOUNDS = 4
    CAPABILITY_PERMISSION = 5
    SECRET_FLOW = 6
    ROOT_LOCKED = 7
    REGION_NESTED = 8
    REGION_STORE_QUOTA = 9
    REGION_BUDGET = 10
    EXPLICIT_TRAP = 11
    DECLASSIFY_DENIED = 12
    INTERRUPT = 13
    DATA_ALIGNMENT = 14
    MEMORY_RANGE = 15
    REGION_REQUIRED = 16
    REGION_REG_QUOTA = 17
    REGION_DEADLINE = 18
    REGION_PREEMPTED = 19
    VRTU_MISS = 20
    VRTU_PERMISSION = 21
    VRTU_CONFLICT = 22
    CAPABILITY_STALE = 23
    CONTRACT_TOKEN = 24
    CONTRACT_ADMISSION = 25
    REGION_ARENA = 26
    REGION_DEVICE = 27
    REGION_CAP_QUOTA = 28
    COMMIT_PROTOCOL = 29
    CAPABILITY_GENERATION_WRAP = 30
    VRTU_CONFIGURATION = 31


@dataclass(frozen=True, slots=True)
class InstructionSpec:
    mnemonic: str
    opcode: Opcode
    fmt: Format
    description: str


_SPECS = [
    InstructionSpec("nop", Opcode.NOP, Format.NONE, "No operation"),
    InstructionSpec("mov", Opcode.MOV, Format.R, "Copy value and metadata"),
    InstructionSpec("movi", Opcode.MOVI, Format.I, "Sign-extended 16-bit immediate"),
    InstructionSpec("lui", Opcode.LUI, Format.I, "Load immediate into upper half"),
    InstructionSpec("add", Opcode.ADD, Format.R, "32-bit addition"),
    InstructionSpec("addi", Opcode.ADDI, Format.I, "32-bit addition with immediate"),
    InstructionSpec("sub", Opcode.SUB, Format.R, "32-bit subtraction"),
    InstructionSpec("mul", Opcode.MUL, Format.R, "Low 32 bits of multiplication"),
    InstructionSpec("and", Opcode.AND, Format.R, "Bitwise AND"),
    InstructionSpec("andi", Opcode.ANDI, Format.I, "Bitwise AND immediate"),
    InstructionSpec("or", Opcode.OR, Format.R, "Bitwise OR"),
    InstructionSpec("ori", Opcode.ORI, Format.I, "Bitwise OR immediate"),
    InstructionSpec("xor", Opcode.XOR, Format.R, "Bitwise XOR"),
    InstructionSpec("xori", Opcode.XORI, Format.I, "Bitwise XOR immediate"),
    InstructionSpec("shl", Opcode.SHL, Format.R, "Logical left shift"),
    InstructionSpec("shr", Opcode.SHR, Format.R, "Logical right shift"),
    InstructionSpec("sar", Opcode.SAR, Format.R, "Arithmetic right shift"),
    InstructionSpec("cmpeq", Opcode.CMPEQ, Format.R, "Equality comparison"),
    InstructionSpec("cmplt", Opcode.CMPLT, Format.R, "Signed less-than comparison"),
    InstructionSpec("cmpult", Opcode.CMPULT, Format.R, "Unsigned less-than comparison"),
    InstructionSpec("brz", Opcode.BRZ, Format.B, "Branch when register is zero"),
    InstructionSpec("brnz", Opcode.BRNZ, Format.B, "Branch when register is non-zero"),
    InstructionSpec("jal", Opcode.JAL, Format.J, "PC-relative jump and link"),
    InstructionSpec("jalr", Opcode.JALR, Format.I, "Register-indirect jump and link"),
    InstructionSpec("halt", Opcode.HALT, Format.NONE, "Stop execution"),
    InstructionSpec("trap", Opcode.TRAP, Format.I, "Raise an explicit trap"),
    InstructionSpec("csrr", Opcode.CSRR, Format.I, "Read a control/status register"),
    InstructionSpec("csrw", Opcode.CSRW, Format.I, "Write a control/status register"),
    InstructionSpec("ei", Opcode.EI, Format.NONE, "Enable external interrupts"),
    InstructionSpec("di", Opcode.DI, Format.NONE, "Disable external interrupts"),
    InstructionSpec("vret", Opcode.VRET, Format.NONE, "Return from trap"),
    InstructionSpec("croot", Opcode.CROOT, Format.R, "Create a root capability before VLOCK"),
    InstructionSpec("cbounds", Opcode.CBOUNDS, Format.R, "Narrow capability bounds"),
    InstructionSpec("cperm", Opcode.CPERM, Format.R, "Narrow capability permissions"),
    InstructionSpec("cinc", Opcode.CINC, Format.R, "Move a capability cursor"),
    InstructionSpec("cgettag", Opcode.CGETTAG, Format.R, "Read capability validity"),
    InstructionSpec("cgetperm", Opcode.CGETPERM, Format.R, "Read capability permissions"),
    InstructionSpec("cldb", Opcode.CLDB, Format.I, "Capability byte load, signed"),
    InstructionSpec("cldbu", Opcode.CLDBU, Format.I, "Capability byte load, unsigned"),
    InstructionSpec("cldh", Opcode.CLDH, Format.I, "Capability halfword load, signed"),
    InstructionSpec("cldhu", Opcode.CLDHU, Format.I, "Capability halfword load, unsigned"),
    InstructionSpec("cldw", Opcode.CLDW, Format.I, "Capability word load"),
    InstructionSpec("cstb", Opcode.CSTB, Format.I, "Capability byte store"),
    InstructionSpec("csth", Opcode.CSTH, Format.I, "Capability halfword store"),
    InstructionSpec("cstw", Opcode.CSTW, Format.I, "Capability word store"),
    InstructionSpec("vdeclass", Opcode.VDECLASS, Format.R, "Explicit declassification with authority"),
    InstructionSpec("vlock", Opcode.VLOCK, Format.NONE, "Irreversibly lock root creation until reset"),
    InstructionSpec("vtry", Opcode.VTRY, Format.VTRY, "Start a bounded atomic Victory Region"),
    InstructionSpec("vchk", Opcode.VCHK, Format.I, "Abort region when condition is false"),
    InstructionSpec("vic", Opcode.VIC, Format.NONE, "Victory Integrity Commit"),
    InstructionSpec("vabt", Opcode.VABT, Format.I, "Explicitly abort a Victory Region"),
    InstructionSpec("verr", Opcode.VERR, Format.R, "Read the last Victory error"),
    InstructionSpec("wfi", Opcode.WFI, Format.NONE, "Wait for interrupt"),
    InstructionSpec("vprep", Opcode.VPREP, Format.R, "Admit a one-shot Victory Contract"),
    InstructionSpec("vtry.c", Opcode.VTRYC, Format.B, "Enter a Victory Region with a prepared contract"),
    InstructionSpec("vcancel", Opcode.VCANCEL, Format.R, "Cancel an unused contract token"),
]

SPECS_BY_MNEMONIC: Final[dict[str, InstructionSpec]] = {spec.mnemonic: spec for spec in _SPECS}
SPECS_BY_OPCODE: Final[dict[Opcode, InstructionSpec]] = {spec.opcode: spec for spec in _SPECS}


@dataclass(frozen=True, slots=True)
class DecodedInstruction:
    word: int
    opcode: Opcode
    rd: int = 0
    rs1: int = 0
    rs2: int = 0
    aux: int = 0
    imm16: int = 0
    off21: int = 0
    stores: int = 0
    budget: int = 0
    off13: int = 0


def mask32(value: int) -> int:
    return value & 0xFFFF_FFFF


def signed32(value: int) -> int:
    value &= 0xFFFF_FFFF
    return value - 0x1_0000_0000 if value & 0x8000_0000 else value


def sign_extend(value: int, bits: int) -> int:
    sign = 1 << (bits - 1)
    value &= (1 << bits) - 1
    return (value ^ sign) - sign


def _reg(value: int) -> int:
    if not 0 <= value < REGISTER_COUNT:
        raise ValueError(f"register index out of range: {value}")
    return value


def _signed_field(value: int, bits: int, name: str) -> int:
    lower = -(1 << (bits - 1))
    upper = (1 << (bits - 1)) - 1
    if not lower <= value <= upper:
        raise ValueError(f"{name} does not fit signed {bits} bits: {value}")
    return value & ((1 << bits) - 1)


def encode_none(opcode: Opcode) -> int:
    return int(opcode) << 26


def encode_r(opcode: Opcode, rd: int, rs1: int = 0, rs2: int = 0, aux: int = 0) -> int:
    if not 0 <= aux <= 0x7FF:
        raise ValueError(f"aux does not fit 11 bits: {aux}")
    return (
        (int(opcode) << 26)
        | (_reg(rd) << 21)
        | (_reg(rs1) << 16)
        | (_reg(rs2) << 11)
        | aux
    )


def encode_i(opcode: Opcode, rd: int = 0, rs1: int = 0, imm16: int = 0) -> int:
    encoded_imm = _signed_field(imm16, 16, "immediate") if imm16 < 0 else imm16
    if not 0 <= encoded_imm <= 0xFFFF:
        raise ValueError(f"immediate does not fit 16 bits: {imm16}")
    return (int(opcode) << 26) | (_reg(rd) << 21) | (_reg(rs1) << 16) | encoded_imm


def encode_b(opcode: Opcode, rs1: int, off_words: int) -> int:
    return (int(opcode) << 26) | (_reg(rs1) << 21) | _signed_field(off_words, 21, "branch offset")


def encode_j(opcode: Opcode, rd: int, off_words: int) -> int:
    return (int(opcode) << 26) | (_reg(rd) << 21) | _signed_field(off_words, 21, "jump offset")


def encode_vtry(stores: int, budget: int, off_words: int) -> int:
    if not 1 <= stores <= 31:
        raise ValueError(f"store quota must be between 1 and 31: {stores}")
    if not 1 <= budget <= 255:
        raise ValueError(f"instruction budget must be between 1 and 255: {budget}")
    return (
        (int(Opcode.VTRY) << 26)
        | (stores << 21)
        | (budget << 13)
        | _signed_field(off_words, 13, "Victory failure offset")
    )


def decode(word: int) -> DecodedInstruction:
    word &= 0xFFFF_FFFF
    raw_opcode = (word >> 26) & 0x3F
    try:
        opcode = Opcode(raw_opcode)
    except ValueError as exc:
        raise ValueError(f"unknown opcode 0x{raw_opcode:02x}") from exc
    branch_rs1 = (word >> 21) & 0x1F if opcode in {Opcode.BRZ, Opcode.BRNZ, Opcode.VTRYC} else (word >> 16) & 0x1F
    return DecodedInstruction(
        word=word,
        opcode=opcode,
        rd=(word >> 21) & 0x1F,
        rs1=branch_rs1,
        rs2=(word >> 11) & 0x1F,
        aux=word & 0x7FF,
        imm16=word & 0xFFFF,
        off21=sign_extend(word & 0x1F_FFFF, 21),
        stores=(word >> 21) & 0x1F,
        budget=(word >> 13) & 0xFF,
        off13=sign_extend(word & 0x1FFF, 13),
    )


def instruction_spec(opcode: Opcode) -> InstructionSpec:
    try:
        return SPECS_BY_OPCODE[opcode]
    except KeyError as exc:
        raise ValueError(f"opcode has no specification: {opcode!r}") from exc
