from __future__ import annotations

import unittest

from victory_v import Machine, assemble
from victory_v.isa import Cause


class SecurityMechanismTests(unittest.TestCase):
    def run_source(self, source: str) -> Machine:
        machine = Machine()
        machine.load_program(assemble(source).words)
        machine.run()
        return machine

    def test_out_of_bounds_store_aborts_region(self) -> None:
        machine = self.run_source(
            """
    li r1, 0x100
    movi r2, 4
    croot c10, r1, r2, rw
    movi r3, 9
    cstw r3, c10, 0
    vtry fail, 1, 8
    movi r4, 55
    cstw r4, c10, 4
    vic
fail:
    verr r5
    halt
"""
        )
        self.assertFalse(machine.faulted)
        self.assertEqual(machine.read_u32(0x100), 9)
        self.assertEqual(machine.registers[5], int(Cause.CAPABILITY_BOUNDS))

    def test_secret_branch_is_rejected_and_secret_register_scrubbed(self) -> None:
        machine = self.run_source(
            """
    li r1, 0x100
    movi r2, 4
    croot c10, r1, r2, rws
    movi r3, 1
    cstw r3, c10, 0
    vtry fail, 1, 8
    cldw s4, c10, 0
    brnz s4, fail
    vic
fail:
    verr r5
    halt
"""
        )
        self.assertFalse(machine.faulted)
        self.assertEqual(machine.registers[5], int(Cause.SECRET_FLOW))
        self.assertEqual(machine.registers[4], 0)
        self.assertFalse(machine.secret_tags[4])

    def test_root_creation_is_locked(self) -> None:
        machine = self.run_source(
            """
    li r1, 0x100
    movi r2, 4
    croot c10, r1, r2, rw
    vlock
    croot c11, r1, r2, rw
    halt
"""
        )
        self.assertTrue(machine.faulted)
        self.assertEqual(machine.vcause, int(Cause.ROOT_LOCKED))
        self.assertFalse(machine.capabilities[11].valid)

    def test_declassification_requires_authority(self) -> None:
        machine = self.run_source(
            """
    li r1, 0x100
    movi r2, 4
    croot c10, r1, r2, rws
    croot c11, r1, r2, d
    movi r3, 5
    cstw r3, c10, 0
    cldw s4, c10, 0
    vdeclass r5, s4, c11
    halt
"""
        )
        self.assertFalse(machine.faulted)
        self.assertEqual(machine.registers[5], 5)
        self.assertFalse(machine.secret_tags[5])


if __name__ == "__main__":
    unittest.main()
