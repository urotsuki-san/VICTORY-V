from __future__ import annotations

import unittest

from victory_v import ContractSpec, Machine, MachineConfig, assemble
from victory_v.isa import Cause


class ContractTests(unittest.TestCase):
    def run_program(self, source: str, *, config: MachineConfig | None = None) -> Machine:
        machine = Machine(config)
        machine.load_program(assemble(source).words)
        machine.run()
        return machine

    def test_contract_spec_round_trip(self) -> None:
        spec = ContractSpec(
            store_granules=3,
            instruction_budget=41,
            register_writes=7,
            capability_allocations=2,
            fixed_release=True,
            secret=True,
            release_delta=63,
        )
        self.assertEqual(ContractSpec.unpack(spec.pack()), spec)
        with self.assertRaises(ValueError):
            ContractSpec(1, 8, 2, secret=True).pack()

    def test_token_is_one_shot_across_register_copies(self) -> None:
        spec = ContractSpec(1, 12, 2).pack()
        machine = self.run_program(
            f"""
    li r1, 0x100
    movi r2, 16
    croot c10, r1, r2, rw
    li r3, {spec}
    vprep c12, c10, r3
    mov c13, c12
    vtry c12, failed
    vic
    vtry c13, failed
    halt
failed:
    halt
"""
        )
        self.assertTrue(machine.faulted)
        self.assertEqual(machine.vcause, int(Cause.CONTRACT_TOKEN))
        self.assertIsNone(machine.admitted_contract)

    def test_cancel_invalidates_all_token_copies(self) -> None:
        spec = ContractSpec(1, 8, 1).pack()
        machine = self.run_program(
            f"""
    li r1, 0x100
    movi r2, 16
    croot c10, r1, r2, rw
    li r3, {spec}
    vprep c12, c10, r3
    mov c13, c12
    vcancel c12
    vtry c13, failed
    halt
failed:
    halt
"""
        )
        self.assertTrue(machine.faulted)
        self.assertEqual(machine.vcause, int(Cause.CONTRACT_TOKEN))

    def test_store_quota_counts_unique_granules(self) -> None:
        spec = ContractSpec(1, 16, 1).pack()
        machine = self.run_program(
            f"""
    li r1, 0x100
    movi r2, 4
    croot c10, r1, r2, rw
    li r3, {spec}
    vprep c12, c10, r3
    vtry c12, failed
    movi r4, 0x11
    cstb r4, c10, 0
    movi r4, 0x22
    cstb r4, c10, 1
    vic
    halt
failed:
    halt
"""
        )
        self.assertFalse(machine.faulted)
        self.assertEqual(machine.read_memory(0x100, 4), bytes((0x11, 0x22, 0, 0)))

    def test_arena_escape_aborts_before_publication(self) -> None:
        spec = ContractSpec(1, 16, 1).pack()
        machine = self.run_program(
            f"""
    li r1, 0x100
    movi r2, 4
    croot c10, r1, r2, rw
    movi r2, 16
    croot c11, r1, r2, rw
    li r3, {spec}
    vprep c12, c10, r3
    vtry c12, failed
    movi r4, 0x55
    cstw r4, c11, 8
    vic
failed:
    halt
"""
        )
        self.assertFalse(machine.faulted)
        self.assertEqual(machine.v_error, int(Cause.REGION_ARENA))
        self.assertEqual(machine.read_u32(0x108), 0)

    def test_device_access_is_rejected_inside_region(self) -> None:
        spec = ContractSpec(1, 16, 1).pack()
        machine = self.run_program(
            f"""
    li r1, 0x180
    movi r2, 16
    croot c10, r1, r2, rw
    li r3, {spec}
    vprep c12, c10, r3
    vtry c12, failed
    movi r4, 0x66
    cstw r4, c10, 0
    vic
failed:
    halt
""",
            config=MachineConfig(memory_size=512, device_base=0x180, device_top=0x190),
        )
        self.assertFalse(machine.faulted)
        self.assertEqual(machine.v_error, int(Cause.REGION_DEVICE))
        self.assertEqual(machine.read_u32(0x180), 0)

    def test_capability_allocation_quota_rolls_back_derived_caps(self) -> None:
        spec = ContractSpec(1, 24, 3, capability_allocations=1).pack()
        machine = self.run_program(
            f"""
    li r1, 0x100
    movi r2, 16
    croot c10, r1, r2, rw
    movi r5, 1
    li r3, {spec}
    vprep c12, c10, r3
    vtry c12, failed
    movi r4, 8
    cbounds c11, c10, r4
    cperm c13, c11, r5
    vic
failed:
    halt
"""
        )
        self.assertFalse(machine.faulted)
        self.assertEqual(machine.v_error, int(Cause.REGION_CAP_QUOTA))
        self.assertFalse(machine.capabilities[11].valid)
        self.assertFalse(machine.capabilities[13].valid)

    def test_fixed_release_holds_commit_until_declared_cycle(self) -> None:
        spec = ContractSpec(1, 20, 1, fixed_release=True, release_delta=24).pack()
        source = f"""
    li r1, 0x100
    movi r2, 4
    croot c10, r1, r2, rw
    li r3, {spec}
    vprep c12, c10, r3
    vtry c12, failed
    movi r4, 42
    cstw r4, c10, 0
    vic
    halt
failed:
    halt
"""
        machine = Machine()
        machine.load_program(assemble(source).words)
        while machine.pending_release is None:
            self.assertTrue(machine.step())
        release_cycle = machine.pending_release.release_cycle
        self.assertEqual(machine.read_u32(0x100), 0)
        while machine.cycle < release_cycle:
            self.assertTrue(machine.step())
            if machine.cycle < release_cycle:
                self.assertEqual(machine.read_u32(0x100), 0)
        self.assertEqual(machine.read_u32(0x100), 42)
        result = machine.run()
        self.assertTrue(result.halted)
        self.assertFalse(result.faulted)

    def test_fixed_release_holds_abort_record(self) -> None:
        spec = ContractSpec(1, 16, 1, fixed_release=True, release_delta=20).pack()
        source = f"""
    li r1, 0x100
    movi r2, 4
    croot c10, r1, r2, rw
    li r3, {spec}
    vprep c12, c10, r3
    vtry c12, failed
    movi r4, 9
    vabt 0x4401
failed:
    halt
"""
        machine = Machine()
        program = assemble(source)
        machine.load_program(program.words)
        while machine.pending_release is None:
            self.assertTrue(machine.step())
        release_cycle = machine.pending_release.release_cycle
        self.assertEqual(machine.v_error, 0)
        while machine.cycle < release_cycle:
            self.assertTrue(machine.step())
            if machine.cycle < release_cycle:
                self.assertEqual(machine.v_error, 0)
        self.assertEqual(machine.v_error, 0x4401)
        self.assertEqual(machine.pc, program.labels["failed"])

    def test_secret_contract_without_fixed_release_is_rejected(self) -> None:
        raw = 1 | (8 << 5) | (1 << 13) | (1 << 24)
        machine = self.run_program(
            f"""
    li r1, 0x100
    movi r2, 4
    croot c10, r1, r2, rws
    li r3, {raw}
    vprep c12, c10, r3
    halt
"""
        )
        self.assertTrue(machine.faulted)
        self.assertEqual(machine.vcause, int(Cause.CONTRACT_ADMISSION))

    def test_admission_rejects_profile_overflow_before_entry(self) -> None:
        spec = ContractSpec(3, 8, 1).pack()
        machine = self.run_program(
            f"""
    li r1, 0x100
    movi r2, 16
    croot c10, r1, r2, rw
    li r3, {spec}
    vprep c12, c10, r3
    halt
""",
            config=MachineConfig(region_store_depth=2),
        )
        self.assertTrue(machine.faulted)
        self.assertEqual(machine.vcause, int(Cause.CONTRACT_ADMISSION))
        self.assertFalse(machine.region.active)


if __name__ == "__main__":
    unittest.main()
