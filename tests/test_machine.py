from __future__ import annotations

import unittest

from victory_v import ContractSpec, Machine, MachineConfig, assemble
from victory_v.isa import Cause


class MachineTests(unittest.TestCase):
    def run_source(
        self, source: str, *, config: MachineConfig | None = None
    ) -> Machine:
        machine = Machine(config)
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


    def test_abort_restores_integer_capability_and_secret_metadata(self) -> None:
        machine = self.run_source(
            """
    li r1, 0x100
    movi r2, 8
    croot c10, r1, r2, rws
    movi r5, 7
    vtry fail, 1, 24
    movi r5, 99
    mov c11, c10
    cldw s12, c10, 0
    vabt 0x3301
fail:
    cgettag r6, c11
    halt
"""
        )
        self.assertEqual(machine.registers[5], 7)
        self.assertFalse(machine.capabilities[11].valid)
        self.assertFalse(machine.secret_tags[12])
        self.assertEqual(machine.registers[6], 0)
        self.assertEqual(machine.v_error, 0x3301)

    def test_same_register_uses_one_log_entry(self) -> None:
        machine = self.run_source(
            """
    movi r5, 7
    vtry fail, 1, 16
    movi r5, 8
    movi r5, 9
    vabt 0x3302
fail:
    halt
"""
        )
        self.assertEqual(machine.registers[5], 7)
        self.assertEqual(machine.last_register_high_water, 1)

    def test_contract_register_quota_aborts_before_unlogged_write(self) -> None:
        spec = ContractSpec(1, 16, 1).pack()
        machine = self.run_source(
            f"""
    li r1, 0x100
    movi r2, 16
    croot c10, r1, r2, rw
    li r3, {spec}
    vprep c12, c10, r3
    movi r5, 5
    movi r6, 6
    vtry c12, fail
    movi r5, 50
    movi r6, 60
    vic
fail:
    halt
"""
        )
        self.assertEqual(machine.registers[5], 5)
        self.assertEqual(machine.registers[6], 6)
        self.assertEqual(machine.v_error, int(Cause.REGION_REG_QUOTA))

    def test_commit_keeps_register_changes(self) -> None:
        machine = self.run_source(
            """
    movi r5, 7
    vtry fail, 1, 8
    movi r5, 99
    vic
    halt
fail:
    halt
"""
        )
        self.assertEqual(machine.registers[5], 99)
        self.assertEqual(machine.last_register_high_water, 1)

    def test_interrupt_aborts_region_before_trap_entry(self) -> None:
        program = assemble(
            """
    movi r1, 0x24
    csrw r1, vtvec
    ei
    movi r5, 7
    vtry fail, 1, 32
    movi r5, 99
    nop
fail:
    halt
    nop
handler:
    halt
"""
        )
        machine = Machine()
        machine.load_program(program.words)
        while not (machine.region.active and machine.registers[5] == 99):
            self.assertTrue(machine.step())
        machine.request_interrupt()
        self.assertTrue(machine.step())
        self.assertEqual(machine.pc, program.labels["handler"])
        self.assertEqual(machine.vepc, program.labels["fail"])
        self.assertEqual(machine.registers[5], 7)
        self.assertEqual(machine.v_error, int(Cause.REGION_PREEMPTED))
        self.assertFalse(machine.region.active)
        result = machine.run()
        self.assertTrue(result.halted)
        self.assertFalse(result.faulted)


if __name__ == "__main__":
    unittest.main()
