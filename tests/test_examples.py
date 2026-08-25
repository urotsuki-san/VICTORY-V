from __future__ import annotations

from pathlib import Path
import unittest

from victory_v import Machine
from victory_v.assembler import assemble_file
from victory_v.isa import Cause


ROOT = Path(__file__).resolve().parents[1]


class ExampleTests(unittest.TestCase):
    def run_example(self, name: str) -> Machine:
        machine = Machine()
        machine.load_program(assemble_file(ROOT / "examples" / name).words)
        result = machine.run()
        self.assertTrue(result.halted, name)
        self.assertFalse(result.faulted, name)
        return machine

    def test_victory(self) -> None:
        machine = self.run_example("victory.vs")
        self.assertEqual(machine.read_u32(0x100), 2)

    def test_rollback(self) -> None:
        machine = self.run_example("rollback.vs")
        self.assertEqual(machine.read_u32(0x100), 7)
        self.assertEqual(machine.v_error, 0x2222)

    def test_capability_fault(self) -> None:
        machine = self.run_example("capability_fault.vs")
        self.assertEqual(machine.read_u32(0x100), 11)
        self.assertEqual(machine.v_error, int(Cause.CAPABILITY_BOUNDS))

    def test_secret_flow(self) -> None:
        machine = self.run_example("secret_flow.vs")
        self.assertEqual(machine.v_error, int(Cause.SECRET_FLOW))
        self.assertEqual(machine.registers[4], 0)


if __name__ == "__main__":
    unittest.main()
