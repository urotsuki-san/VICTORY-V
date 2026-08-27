from __future__ import annotations

import unittest

from victory_v.family import (
    ARCHITECTURES,
    DECISION_ENGINES,
    EUCLID_EXPERIMENT,
    FAMILY_RULES,
    SYSTEM_PROFILES,
    VRTU_E0,
    VRTU_P0,
    VV32_A0,
    VV64_A0,
    validate_family,
)


class FamilyProfileTests(unittest.TestCase):
    def test_family_contract_is_valid(self) -> None:
        validate_family()

    def test_vv32_is_the_source_architecture(self) -> None:
        self.assertIsNone(VV32_A0.inherits)
        self.assertEqual(VV32_A0.required_rules, FAMILY_RULES)
        self.assertEqual(VV32_A0.translation, "none")

    def test_vv64_has_exact_range_translation(self) -> None:
        self.assertEqual(VV64_A0.inherits, "VV32-A0")
        self.assertTrue(FAMILY_RULES <= VV64_A0.required_rules)
        self.assertEqual(VV64_A0.translation, "range")
        self.assertIn("exact_range_translation", VV64_A0.required_rules)

    def test_nommu_profile_uses_vrtu_protection(self) -> None:
        flat = SYSTEM_PROFILES["VV64-L0-flat"]
        paged = SYSTEM_PROFILES["VV64-L0-paged"]
        self.assertFalse(flat.mmu)
        self.assertIn("VRTU", flat.protection)
        self.assertIsNone(flat.virtual_address_bits)
        self.assertTrue(paged.mmu)
        self.assertEqual(paged.virtual_address_bits, 39)
        self.assertIn(flat.architecture, ARCHITECTURES)

    def test_contract_capacity_includes_vrtu_entries(self) -> None:
        self.assertGreater(VRTU_P0.entries, VRTU_E0.entries)
        self.assertFalse(VRTU_P0.software_refill)
        self.assertFalse(VRTU_E0.page_walker)
        self.assertEqual(VRTU_P0.address_bits, 17)

    def test_euclid_is_archived_not_shipped(self) -> None:
        self.assertIs(DECISION_ENGINES["EUCLID-experiment"], EUCLID_EXPERIMENT)
        self.assertEqual(EUCLID_EXPERIMENT.status, "experiment")
        self.assertFalse(EUCLID_EXPERIMENT.cpu_visible)
        self.assertIn("not in the FPGA image", EUCLID_EXPERIMENT.hardware_target)


if __name__ == "__main__":
    unittest.main()
