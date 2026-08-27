#!/usr/bin/env python3
"""Regenerate the fixed ROM used by the Tang 138K bring-up image."""

from __future__ import annotations

from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from victory_v import assemble  # noqa: E402
from victory_v.disassembler import disassemble_word  # noqa: E402

BootImage = tuple[str, str, int, int, bool]

IMAGES: tuple[BootImage, ...] = (
    ("vv32_bringup_rom", "VV32-A0 VTRY ready\r\n", 0x10, 0x32, False),
    ("vv64_p_bringup_rom", "VV64-P0 VTRY ready\r\n", 0x18, 0x50, True),
    ("vv64_e_bringup_rom", "VV64-E0 VTRY ready\r\n", 0x20, 0x45, True),
)

LEGACY_IMAGE: BootImage = (
    "vv64_bringup_rom",
    "VV64-A0 VTRY ready\r\n",
    0x18,
    0x64,
    False,
)


def emit_bytes(register: str, payload: bytes) -> list[str]:
    lines: list[str] = []
    for byte in payload:
        lines.append(f"    movi r3, 0x{byte:02x}")
        lines.append(f"    cstb r3, {register}, 0")
    return lines


def source(image: BootImage) -> str:
    _, message, mailbox_offset, marker, has_vrtu = image
    direct_value = 0x1000 | marker
    prepared_value = 0x2000 | marker
    abort_value = 0x3000 | marker

    lines = [
        "    movi r1, 0",
        "    lui r2, 2",
        "    croot c10, r1, r2, rw",
        "    vlock",
        "    lui r4, 1",
        "    cinc c11, c10, r4",
        "",
        "    movi r7, 0x100",
        "    cinc c13, c10, r7",
        "    movi r8, 16",
        "    cbounds c13, c13, r8",
        "",
        f"    movi r6, 0x{direct_value:04x}",
        "    vtry direct_fail, 1, 8",
        "    cstw r6, c13, 0",
        "    vic",
        "    cldw r7, c13, 0",
        f"    movi r8, 0x{direct_value:04x}",
        "    cmpeq r9, r7, r8",
        "    brz r9, direct_fail",
        "",
        "    movi r9, 0x4101",
        "    vprep c14, c13, r9",
        "    vtry c14, prepared_fail",
        f"    movi r6, 0x{prepared_value:04x}",
        "    cstw r6, c13, 4",
        "    vic",
        "    cldw r7, c13, 4",
        f"    movi r8, 0x{prepared_value:04x}",
        "    cmpeq r9, r7, r8",
        "    brz r9, prepared_fail",
        "",
        f"    movi r6, 0x{abort_value:04x}",
        "    vtry abort_check, 1, 8",
        "    cstw r6, c13, 8",
        "    vabt 0x7001",
        "abort_check:",
        "    cldw r7, c13, 8",
        "    brnz r7, abort_fail",
        "    verr r8",
        "    movi r9, 0x7001",
        "    cmpeq r9, r8, r9",
        "    brz r9, abort_fail",
        "",
    ]

    if has_vrtu:
        lines.extend(
            [
                "    movi r6, 0x1234",
                "    vtry device_check, 1, 8",
                "    cstw r6, c11, 0",
                "    vic",
                "device_check:",
                "    verr r8",
                "    movi r9, 27",
                "    cmpeq r9, r8, r9",
                "    brz r9, device_fail",
                "",
            ]
        )

    lines.extend(
        [
            "    movi r8, 0",
            "    csrw r8, verror",
            "    jmp selftest_ok",
            "",
            "direct_fail:",
            "    movi r6, 0x31",
            "    jmp selftest_fail",
            "prepared_fail:",
            "    movi r6, 0x32",
            "    jmp selftest_fail",
            "abort_fail:",
            "    movi r6, 0x33",
            "    jmp selftest_fail",
        ]
    )
    if has_vrtu:
        lines.extend(
            [
                "device_fail:",
                "    movi r6, 0x34",
                "    jmp selftest_fail",
            ]
        )

    lines.extend(["", "selftest_fail:"])
    lines.extend(emit_bytes("c11", b"VTRY FAIL "))
    lines.extend(
        [
            "    cstb r6, c11, 0",
            "    movi r3, 0x0d",
            "    cstb r3, c11, 0",
            "    movi r3, 0x0a",
            "    cstb r3, c11, 0",
            "    halt",
            "",
            "selftest_ok:",
        ]
    )
    lines.extend(emit_bytes("c11", message.encode("ascii")))
    lines.extend(
        [
            f"    movi r5, 0x{mailbox_offset:02x}",
            "    cinc c12, c11, r5",
            f"    movi r6, 0x{marker:02x}",
            "    cstw r6, c12, 0",
            "    movi r5, 0x28",
            "    cinc c12, c11, r5",
            f"    movi r6, 0x{marker:02x}",
            "    cstw r6, c12, 0",
            "    halt",
        ]
    )
    return "\n".join(lines) + "\n"


def program(image: BootImage) -> list[tuple[int, str]]:
    assembled = assemble(source(image))
    return [
        (word, disassemble_word(word, pc=index * 4))
        for index, word in enumerate(assembled.words)
    ]


def render_module(image: BootImage) -> list[str]:
    module_name, _, _, _, _ = image
    lines = [
        f"module {module_name} (",
        "  input  logic [63:0] addr_i,",
        "  output logic [31:0] data_o",
        ");",
        "  always_comb begin",
        "    data_o = 32'h0000_0000;",
        "    case (addr_i[9:2])",
    ]
    lines.extend(
        f"      8'd{index}: data_o = 32'h{word:08x}; // {note}"
        for index, (word, note) in enumerate(program(image))
    )
    lines.extend(["      default: ;", "    endcase", "  end", "endmodule", ""])
    return lines


def render() -> str:
    lines = [
        "// Generated by tools/gen_fpga_bringup.py. Keep the script and this file together.",
        "// Each core checks direct VTRY commit, prepared VTRY commit, and rollback before UART.",
        "// VV64 also checks that a Region cannot publish to the VRTU DEVICE range.",
        "// Success prints VTRY ready; failure prints VTRY FAIL plus the failed stage.",
        "`timescale 1ns/1ps",
        "",
    ]
    for image in IMAGES:
        lines.extend(render_module(image))
    # Keep the old two-core testbench useful while the board projects use P0/E0.
    lines.extend(render_module(LEGACY_IMAGE))
    return "\n".join(lines)


def main() -> None:
    output = ROOT / "rtl" / "boot" / "vv_bringup_rom.sv"
    output.write_text(render(), encoding="utf-8")


if __name__ == "__main__":
    main()
