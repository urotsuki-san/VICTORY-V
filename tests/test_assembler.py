from __future__ import annotations

import unittest

from victory_v.assembler import AssemblyError, assemble, parse_permission
from victory_v.isa import CapabilityPermission, Opcode, decode


class AssemblerTests(unittest.TestCase):
    def test_labels_and_relative_branch(self) -> None:
        program = assemble(
            """
start:
    movi r1, 1
    brz r1, done
    jmp start
done:
    halt
"""
        )
        self.assertEqual(len(program.words), 4)
        branch = decode(program.words[1])
        jump = decode(program.words[2])
        self.assertEqual(branch.opcode, Opcode.BRZ)
        self.assertEqual(branch.off21, 1)
        self.assertEqual(jump.opcode, Opcode.JAL)
        self.assertEqual(jump.rd, 0)
        self.assertEqual(jump.off21, -3)

    def test_li_expands_to_two_words_for_32_bit_value(self) -> None:
        program = assemble("li r3, 0x12345678\nhalt\n")
        self.assertEqual(len(program.words), 3)
        self.assertEqual(decode(program.words[0]).opcode, Opcode.LUI)
        self.assertEqual(decode(program.words[1]).opcode, Opcode.ORI)

    def test_permission_letters(self) -> None:
        self.assertEqual(
            parse_permission("rwsd"),
            int(
                CapabilityPermission.READ
                | CapabilityPermission.WRITE
                | CapabilityPermission.SECRET
                | CapabilityPermission.DECLASSIFY
            ),
        )

    def test_duplicate_label_is_rejected(self) -> None:
        with self.assertRaises(AssemblyError):
            assemble("same:\n nop\nsame:\n halt\n")


if __name__ == "__main__":
    unittest.main()
