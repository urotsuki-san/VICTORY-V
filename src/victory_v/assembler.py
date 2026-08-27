"""Two-pass assembler for the VICTORY-V VV32-A0 ISA."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import re
import struct
from typing import Iterable, Sequence

from .errors import AssemblyError
from .isa import (
    CapabilityPermission,
    Csr,
    Opcode,
    REGISTER_COUNT,
    encode_b,
    encode_i,
    encode_j,
    encode_none,
    encode_r,
    encode_vtry,
)

_LABEL_RE = re.compile(r"^[A-Za-z_.$][A-Za-z0-9_.$]*$")
_REGISTER_RE = re.compile(r"^[rvcs](\d+)$", re.IGNORECASE)


@dataclass(frozen=True, slots=True)
class ParsedLine:
    line_number: int
    original: str
    label: str | None
    mnemonic: str | None
    operands: tuple[str, ...]


@dataclass(frozen=True, slots=True)
class AssembledProgram:
    words: tuple[int, ...]
    labels: dict[str, int]
    source_map: dict[int, int]

    def to_bytes(self) -> bytes:
        return b"".join(struct.pack("<I", word) for word in self.words)

    def write(self, path: str | Path) -> None:
        Path(path).write_bytes(self.to_bytes())


def _strip_comment(text: str) -> str:
    semicolon = text.find(";")
    slash = text.find("//")
    positions = [position for position in (semicolon, slash) if position >= 0]
    return text[: min(positions)] if positions else text


def _split_operands(text: str) -> tuple[str, ...]:
    if not text.strip():
        return ()
    return tuple(part.strip() for part in text.split(",") if part.strip())


def _parse_lines(source: str) -> list[ParsedLine]:
    parsed: list[ParsedLine] = []
    for line_number, original in enumerate(source.splitlines(), start=1):
        text = _strip_comment(original).strip()
        if not text:
            continue

        label: str | None = None
        if ":" in text:
            possible, remainder = text.split(":", 1)
            possible = possible.strip()
            if not _LABEL_RE.match(possible):
                raise AssemblyError("invalid label", line=line_number, source=original)
            label = possible
            text = remainder.strip()

        if not text:
            parsed.append(ParsedLine(line_number, original, label, None, ()))
            continue

        pieces = text.split(None, 1)
        mnemonic = pieces[0].lower()
        operands = _split_operands(pieces[1] if len(pieces) == 2 else "")
        parsed.append(ParsedLine(line_number, original, label, mnemonic, operands))
    return parsed


def parse_number(token: str) -> int:
    token = token.strip()
    if token.startswith("#"):
        token = token[1:].strip()
    token = token.replace("_", "")
    if not token:
        raise ValueError("empty number")
    return int(token, 0)


def parse_register(token: str) -> int:
    token = token.strip().lower()
    aliases = {
        "zero": 0,
        "sp": 29,
        "fp": 30,
        "lr": 31,
    }
    if token in aliases:
        return aliases[token]
    match = _REGISTER_RE.match(token)
    if not match:
        raise ValueError(f"invalid register: {token}")
    index = int(match.group(1))
    if not 0 <= index < REGISTER_COUNT:
        raise ValueError(f"register out of range: {token}")
    return index


def parse_permission(token: str) -> int:
    raw = token.strip().lower()
    try:
        numeric = parse_number(raw)
    except ValueError:
        numeric = -1
    if numeric >= 0:
        if numeric > 0x1F:
            raise ValueError("capability permission mask exceeds five bits")
        return numeric

    if raw in {"none", "-"}:
        return 0
    mapping = {
        "r": CapabilityPermission.READ,
        "w": CapabilityPermission.WRITE,
        "x": CapabilityPermission.EXECUTE,
        "s": CapabilityPermission.SECRET,
        "d": CapabilityPermission.DECLASSIFY,
    }
    mask = CapabilityPermission(0)
    for character in raw:
        try:
            mask |= mapping[character]
        except KeyError as exc:
            raise ValueError(f"unknown capability permission: {character}") from exc
    return int(mask)


def parse_csr(token: str) -> int:
    raw = token.strip().upper()
    if raw in Csr.__members__:
        return int(Csr[raw])
    value = parse_number(token)
    if not 0 <= value <= 0xFFFF:
        raise ValueError("CSR index does not fit 16 bits")
    return value


def _li_word_count(value: int) -> int:
    return 1 if -0x8000 <= value <= 0x7FFF else 2


def _word_count(line: ParsedLine) -> int:
    if line.mnemonic is None:
        return 0
    if line.mnemonic == "li":
        if len(line.operands) != 2:
            raise AssemblyError("li expects two operands", line=line.line_number, source=line.original)
        try:
            return _li_word_count(parse_number(line.operands[1]))
        except ValueError as exc:
            raise AssemblyError(str(exc), line=line.line_number, source=line.original) from exc
    return 1


def _require_count(line: ParsedLine, expected: int) -> None:
    if len(line.operands) != expected:
        raise AssemblyError(
            f"{line.mnemonic} expects {expected} operand(s), got {len(line.operands)}",
            line=line.line_number,
            source=line.original,
        )


def _relative_offset(label: str, labels: dict[str, int], pc: int, bits: int, line: ParsedLine) -> int:
    try:
        target = labels[label]
    except KeyError as exc:
        raise AssemblyError(f"unknown label: {label}", line=line.line_number, source=line.original) from exc
    delta = target - (pc + 4)
    if delta % 4:
        raise AssemblyError("branch target is not word aligned", line=line.line_number, source=line.original)
    words = delta // 4
    minimum = -(1 << (bits - 1))
    maximum = (1 << (bits - 1)) - 1
    if not minimum <= words <= maximum:
        raise AssemblyError(
            f"relative target does not fit signed {bits}-bit word offset",
            line=line.line_number,
            source=line.original,
        )
    return words


def _number(token: str, line: ParsedLine) -> int:
    try:
        return parse_number(token)
    except ValueError as exc:
        raise AssemblyError(str(exc), line=line.line_number, source=line.original) from exc


def _register(token: str, line: ParsedLine) -> int:
    try:
        return parse_register(token)
    except ValueError as exc:
        raise AssemblyError(str(exc), line=line.line_number, source=line.original) from exc


def _permission(token: str, line: ParsedLine) -> int:
    try:
        return parse_permission(token)
    except ValueError as exc:
        raise AssemblyError(str(exc), line=line.line_number, source=line.original) from exc


def _csr(token: str, line: ParsedLine) -> int:
    try:
        return parse_csr(token)
    except ValueError as exc:
        raise AssemblyError(str(exc), line=line.line_number, source=line.original) from exc


def _encode_line(line: ParsedLine, labels: dict[str, int], pc: int) -> list[int]:
    mnemonic = line.mnemonic
    assert mnemonic is not None
    op = line.operands

    # Pseudo-instructions.
    if mnemonic == "li":
        _require_count(line, 2)
        rd = _register(op[0], line)
        value = _number(op[1], line)
        if not -0x8000_0000 <= value <= 0xFFFF_FFFF:
            raise AssemblyError("li value does not fit 32 bits", line=line.line_number, source=line.original)
        value &= 0xFFFF_FFFF
        signed = value - 0x1_0000_0000 if value & 0x8000_0000 else value
        if -0x8000 <= signed <= 0x7FFF:
            return [encode_i(Opcode.MOVI, rd, 0, signed)]
        return [
            encode_i(Opcode.LUI, rd, 0, (value >> 16) & 0xFFFF),
            encode_i(Opcode.ORI, rd, rd, value & 0xFFFF),
        ]
    if mnemonic == "jmp":
        _require_count(line, 1)
        return [encode_j(Opcode.JAL, 0, _relative_offset(op[0], labels, pc, 21, line))]
    if mnemonic == "call":
        _require_count(line, 1)
        return [encode_j(Opcode.JAL, 31, _relative_offset(op[0], labels, pc, 21, line))]
    if mnemonic == "ret":
        _require_count(line, 0)
        return [encode_i(Opcode.JALR, 0, 31, 0)]
    if mnemonic == "clr":
        _require_count(line, 1)
        return [encode_i(Opcode.MOVI, _register(op[0], line), 0, 0)]
    if mnemonic == ".word":
        _require_count(line, 1)
        value = _number(op[0], line)
        if not -0x8000_0000 <= value <= 0xFFFF_FFFF:
            raise AssemblyError(".word value does not fit 32 bits", line=line.line_number, source=line.original)
        return [value & 0xFFFF_FFFF]

    none_ops = {
        "nop": Opcode.NOP,
        "halt": Opcode.HALT,
        "ei": Opcode.EI,
        "di": Opcode.DI,
        "vret": Opcode.VRET,
        "vlock": Opcode.VLOCK,
        "vic": Opcode.VIC,
        "wfi": Opcode.WFI,
    }
    if mnemonic in none_ops:
        _require_count(line, 0)
        return [encode_none(none_ops[mnemonic])]

    three_register_ops = {
        "add": Opcode.ADD,
        "sub": Opcode.SUB,
        "mul": Opcode.MUL,
        "and": Opcode.AND,
        "or": Opcode.OR,
        "xor": Opcode.XOR,
        "shl": Opcode.SHL,
        "shr": Opcode.SHR,
        "sar": Opcode.SAR,
        "cmpeq": Opcode.CMPEQ,
        "cmplt": Opcode.CMPLT,
        "cmpult": Opcode.CMPULT,
        "cbounds": Opcode.CBOUNDS,
        "cperm": Opcode.CPERM,
        "cinc": Opcode.CINC,
        "vdeclass": Opcode.VDECLASS,
    }
    if mnemonic in three_register_ops:
        _require_count(line, 3)
        return [
            encode_r(
                three_register_ops[mnemonic],
                _register(op[0], line),
                _register(op[1], line),
                _register(op[2], line),
            )
        ]

    if mnemonic == "mov":
        _require_count(line, 2)
        return [encode_r(Opcode.MOV, _register(op[0], line), _register(op[1], line))]

    if mnemonic == "croot":
        _require_count(line, 4)
        return [
            encode_r(
                Opcode.CROOT,
                _register(op[0], line),
                _register(op[1], line),
                _register(op[2], line),
                _permission(op[3], line),
            )
        ]

    if mnemonic in {"cgettag", "cgetperm"}:
        _require_count(line, 2)
        opcode = Opcode.CGETTAG if mnemonic == "cgettag" else Opcode.CGETPERM
        return [encode_r(opcode, _register(op[0], line), _register(op[1], line))]

    if mnemonic == "verr":
        _require_count(line, 1)
        return [encode_r(Opcode.VERR, _register(op[0], line))]

    if mnemonic in {"movi", "lui"}:
        _require_count(line, 2)
        opcode = Opcode.MOVI if mnemonic == "movi" else Opcode.LUI
        return [encode_i(opcode, _register(op[0], line), 0, _number(op[1], line))]

    immediate_ops = {
        "addi": Opcode.ADDI,
        "andi": Opcode.ANDI,
        "ori": Opcode.ORI,
        "xori": Opcode.XORI,
        "jalr": Opcode.JALR,
        "cldb": Opcode.CLDB,
        "cldbu": Opcode.CLDBU,
        "cldh": Opcode.CLDH,
        "cldhu": Opcode.CLDHU,
        "cldw": Opcode.CLDW,
        "cstb": Opcode.CSTB,
        "csth": Opcode.CSTH,
        "cstw": Opcode.CSTW,
    }
    if mnemonic in immediate_ops:
        _require_count(line, 3)
        return [
            encode_i(
                immediate_ops[mnemonic],
                _register(op[0], line),
                _register(op[1], line),
                _number(op[2], line),
            )
        ]

    if mnemonic in {"brz", "brnz"}:
        _require_count(line, 2)
        opcode = Opcode.BRZ if mnemonic == "brz" else Opcode.BRNZ
        return [encode_b(opcode, _register(op[0], line), _relative_offset(op[1], labels, pc, 21, line))]

    if mnemonic == "jal":
        _require_count(line, 2)
        return [encode_j(Opcode.JAL, _register(op[0], line), _relative_offset(op[1], labels, pc, 21, line))]

    if mnemonic == "trap":
        _require_count(line, 1)
        return [encode_i(Opcode.TRAP, 0, 0, _number(op[0], line))]

    if mnemonic == "csrr":
        _require_count(line, 2)
        return [encode_i(Opcode.CSRR, _register(op[0], line), 0, _csr(op[1], line))]

    if mnemonic == "csrw":
        _require_count(line, 2)
        return [encode_i(Opcode.CSRW, 0, _register(op[0], line), _csr(op[1], line))]

    if mnemonic == "vprep":
        _require_count(line, 3)
        return [
            encode_r(
                Opcode.VPREP,
                _register(op[0], line),
                _register(op[1], line),
                _register(op[2], line),
            )
        ]

    if mnemonic == "vcancel":
        _require_count(line, 1)
        return [encode_r(Opcode.VCANCEL, 0, _register(op[0], line))]

    if mnemonic in {"vtry", "vtry.c"}:
        if mnemonic == "vtry.c" or len(op) == 2:
            _require_count(line, 2)
            return [
                encode_b(
                    Opcode.VTRYC,
                    _register(op[0], line),
                    _relative_offset(op[1], labels, pc, 21, line),
                )
            ]
        if len(op) == 3:
            stores = _number(op[1], line)
            budget = _number(op[2], line)
            return [encode_vtry(stores, budget, _relative_offset(op[0], labels, pc, 13, line))]
        raise AssemblyError(
            "vtry expects either cToken, target or target, stores, budget",
            line=line.line_number,
            source=line.original,
        )

    if mnemonic == "vchk":
        _require_count(line, 2)
        return [encode_i(Opcode.VCHK, 0, _register(op[0], line), _number(op[1], line))]

    if mnemonic == "vabt":
        _require_count(line, 1)
        return [encode_i(Opcode.VABT, 0, 0, _number(op[0], line))]

    raise AssemblyError(f"unknown instruction: {mnemonic}", line=line.line_number, source=line.original)


def assemble(source: str) -> AssembledProgram:
    parsed = _parse_lines(source)
    labels: dict[str, int] = {}
    pc = 0
    for line in parsed:
        if line.label is not None:
            if line.label in labels:
                raise AssemblyError(f"duplicate label: {line.label}", line=line.line_number, source=line.original)
            labels[line.label] = pc
        pc += 4 * _word_count(line)

    words: list[int] = []
    source_map: dict[int, int] = {}
    pc = 0
    for line in parsed:
        if line.mnemonic is None:
            continue
        encoded = _encode_line(line, labels, pc)
        for word in encoded:
            source_map[pc] = line.line_number
            words.append(word & 0xFFFF_FFFF)
            pc += 4
    return AssembledProgram(tuple(words), labels, source_map)


def assemble_lines(lines: Iterable[str]) -> AssembledProgram:
    return assemble("\n".join(lines))


def assemble_file(path: str | Path) -> AssembledProgram:
    return assemble(Path(path).read_text(encoding="utf-8"))


def words_from_bytes(data: bytes) -> tuple[int, ...]:
    if len(data) % 4:
        raise ValueError("program byte length must be a multiple of four")
    return tuple(word[0] for word in struct.iter_unpack("<I", data))


def words_to_bytes(words: Sequence[int]) -> bytes:
    return b"".join(struct.pack("<I", word & 0xFFFF_FFFF) for word in words)
