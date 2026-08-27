from __future__ import annotations

import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class Tang138KPlatformTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.platform = json.loads(
            (ROOT / "platform" / "tang-138k-1p1e1v32.json").read_text(encoding="utf-8")
        )

    def test_three_core_shape(self) -> None:
        cores = self.platform["cores"]
        self.assertEqual([core["id"] for core in cores], [0, 1, 2])
        self.assertEqual([core["architecture"] for core in cores], ["VV32-A0", "VV64-A0", "VV64-A0"])
        self.assertEqual([core["implementation"] for core in cores], ["control", "P0", "E0"])
        self.assertNotIn("euclid", self.platform)

    def test_p_and_e_share_isa_but_not_contract_capacity(self) -> None:
        p_core, e_core = self.platform["cores"][1:]
        self.assertEqual(p_core["architecture"], e_core["architecture"])
        self.assertGreater(p_core["capability_directory_entries"], e_core["capability_directory_entries"])
        self.assertGreater(p_core["store_buffer_entries"], e_core["store_buffer_entries"])
        self.assertGreater(p_core["vrtu_entries"], e_core["vrtu_entries"])

    def test_linux_target_is_nommu_with_vrtu(self) -> None:
        target = self.platform["linux_target"]
        self.assertEqual(target["profile"], "VV64-L0-flat")
        self.assertFalse(target["mmu"])
        self.assertEqual(target["memory_protection"], "VRTU")
        self.assertEqual(target["primary_core"], 1)

    def test_vrtu_has_no_refill_or_walker(self) -> None:
        vrtu = self.platform["vrtu"]
        self.assertFalse(vrtu["software_refill"])
        self.assertFalse(vrtu["page_table_walker"])
        self.assertEqual(vrtu["overlap_policy"], "fault")
        self.assertEqual(vrtu["causes"], {"miss": 20, "permission": 21, "conflict": 22})

    def test_mmio_is_unique_and_inside_root(self) -> None:
        addresses = list(self.platform["mmio"].values())
        self.assertEqual(len(addresses), len(set(addresses)))
        self.assertGreaterEqual(min(addresses), self.platform["memory"]["mmio_base"])
        self.assertLess(max(addresses), self.platform["memory"]["capability_root_end"])


if __name__ == "__main__":
    unittest.main()
