from __future__ import annotations

import unittest

from victory_v.family import ARCHITECTURES, FAMILY_RULES, SYSTEM_PROFILES, VV32_A0, VV64_A0, validate_family


class FamilyProfileTests(unittest.TestCase):
    def test_family_contract_is_valid(self) -> None:
        validate_family()

    def test_vv32_is_the_source_architecture(self) -> None:
        self.assertIsNone(VV32_A0.inherits)
        self.assertEqual(VV32_A0.required_rules, FAMILY_RULES)
        self.assertEqual(VV32_A0.translation, "none")

    def test_vv64_inherits_instead_of_replacing_vv32(self) -> None:
        self.assertEqual(VV64_A0.inherits, "VV32-A0")
        self.assertTrue(FAMILY_RULES <= VV64_A0.required_rules)
        self.assertEqual(VV64_A0.xlen, 64)
        self.assertEqual(VV64_A0.translation, "optional")

    def test_linux_has_flat_and_paged_profiles(self) -> None:
        flat = SYSTEM_PROFILES["VV64-L0-flat"]
        paged = SYSTEM_PROFILES["VV64-L0-paged"]
        self.assertFalse(flat.mmu)
        self.assertIsNone(flat.virtual_address_bits)
        self.assertTrue(paged.mmu)
        self.assertEqual(paged.virtual_address_bits, 39)
        self.assertEqual(flat.architecture, paged.architecture)
        self.assertIn(flat.architecture, ARCHITECTURES)


if __name__ == "__main__":
    unittest.main()
