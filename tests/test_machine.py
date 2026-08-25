from __future__ import annotations

import unittest

from victory_v import Machine, assemble
from victory_v.isa import Cause


class MachineTests(unittest.TestCase):
    def run_source(self, source: str) -> Machine:
        machine = Machine()
        machine.load_program(assemble(source).words)
        result = machine.run()
        self.assertFalse(result.faulted)
        self.assertTrue(result.halted)
        return machine

    def test_integer_operations_and_zero_register(self) -> None:
        machine = self.run_source(
            """
    movi r1, 20
    movi r2, 22
    add r3, r1, r2
    movi r0, 7
    halt
"""
        )
        self.assertEqual(machine.registers[3], 42)
        self.assertEqual(machine.registers[0], 0)
        self.assertFalse(machine.capabilities[0].valid)

    def test_victory_commit(self) -> None:
        machine = self.run_source(
            """
    li r1, 0x100
    movi r2, 4
    croot c10, r1, r2, rw
    vtry fail, 1, 8
    movi r3, 42
    cstw r3, c10, 0
    movi r4, 1
    vchk r4, 0x55
    vic
    halt
fail:
    halt
"""
        )
        self.assertEqual(machine.read_u32(0x100), 42)
        self.assertEqual(machine.v_error, 0)

    def test_store_forwarding_inside_region(self) -> None:
        machine = self.run_source(
            """
    li r1, 0x100
    movi r2, 4
    croot c10, r1, r2, rw
    vtry fail, 1, 8
    movi r3, 0x1234
    cstw r3, c10, 0
    cldw r4, c10, 0
    cmpeq r5, r3, r4
    vchk r5, 0x77
    vic
    halt
fail:
    halt
"""
        )
        self.assertEqual(machine.registers[4], 0x1234)
        self.assertEqual(machine.read_u32(0x100), 0x1234)

    def test_victory_rollback(self) -> None:
        machine = self.run_source(
            """
    li r1, 0x100
    movi r2, 4
    croot c10, r1, r2, rw
    movi r3, 7
    cstw r3, c10, 0
    vtry fail, 1, 8
    movi r4, 99
    cstw r4, c10, 0
    clr r5
    vchk r5, 0x2222
    vic
fail:
    halt
"""
        )
        self.assertEqual(machine.read_u32(0x100), 7)
        self.assertEqual(machine.v_error, 0x2222)

    def test_region_budget_aborts(self) -> None:
        machine = self.run_source(
            """
    vtry fail, 1, 2
    nop
    nop
    nop
    vic
fail:
    verr r1
    halt
"""
        )
        self.assertEqual(machine.registers[1], int(Cause.REGION_BUDGET))


if __name__ == "__main__":
    unittest.main()
