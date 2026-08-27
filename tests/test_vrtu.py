from __future__ import annotations

import unittest

from victory_v.vrtu import (
    Vrtu,
    VrtuAccess,
    VrtuCause,
    VrtuFault,
    VrtuPermission,
    tang138k_nommu_vrtu,
)


class VrtuTests(unittest.TestCase):
    def test_flat_ram_and_mmio_reset_map(self) -> None:
        vrtu = tang138k_nommu_vrtu(performance_profile=True)
        self.assertEqual(vrtu.translate(0x40, size=4, access=VrtuAccess.EXECUTE, user=True), 0x40)
        self.assertEqual(vrtu.translate(0x200, size=8, access=VrtuAccess.WRITE, user=True), 0x200)
        self.assertEqual(vrtu.translate(0x10020, size=8, access=VrtuAccess.WRITE), 0x10020)

    def test_mmio_is_not_executable_or_user_accessible(self) -> None:
        vrtu = tang138k_nommu_vrtu(performance_profile=False)
        for access, user in ((VrtuAccess.EXECUTE, False), (VrtuAccess.READ, True)):
            with self.assertRaises(VrtuFault) as caught:
                vrtu.translate(0x10000, size=4, access=access, user=user)
            self.assertEqual(caught.exception.cause, VrtuCause.PERMISSION)

    def test_unmapped_range_is_exact_fault(self) -> None:
        vrtu = tang138k_nommu_vrtu(performance_profile=True)
        with self.assertRaises(VrtuFault) as caught:
            vrtu.translate(0x20000, size=4, access=VrtuAccess.READ)
        self.assertEqual(caught.exception.cause, VrtuCause.MISS)

    def test_offset_translation_and_guard_invalidation(self) -> None:
        vrtu = Vrtu(2, physical_bits=20)
        perms = int(VrtuPermission.READ | VrtuPermission.WRITE | VrtuPermission.USER)
        vrtu.configure(0, valid=True, vbase=0x4000, vtop=0x5000, pbase=0x8000, permissions=perms)
        self.assertEqual(vrtu.translate(0x4120, size=8, access=VrtuAccess.READ, user=True), 0x8120)
        vrtu.configure(0, valid=True, vbase=0x4000, vtop=0x5000, pbase=0xA000, permissions=perms)
        self.assertEqual(vrtu.translate(0x4120, size=8, access=VrtuAccess.READ, user=True), 0xA120)

    def test_overlap_is_rejected_at_configuration(self) -> None:
        vrtu = Vrtu(2)
        perms = int(VrtuPermission.READ)
        vrtu.configure(0, valid=True, vbase=0, vtop=0x1000, pbase=0, permissions=perms)
        with self.assertRaises(ValueError):
            vrtu.configure(1, valid=True, vbase=0x800, vtop=0x1800, pbase=0x2000, permissions=perms)

    def test_region_cannot_reach_device_descriptor(self) -> None:
        vrtu = tang138k_nommu_vrtu(performance_profile=True)
        with self.assertRaises(VrtuFault) as caught:
            vrtu.translate(
                0x10000,
                size=4,
                access=VrtuAccess.WRITE,
                region_active=True,
            )
        self.assertEqual(caught.exception.cause, VrtuCause.DEVICE)

    def test_parent_capability_can_only_be_attenuated(self) -> None:
        vrtu = Vrtu(2, physical_bits=20)
        vrtu.configure_from_capability(
            0,
            valid=True,
            vbase=0x4000,
            vtop=0x4400,
            pbase=0x8000,
            permissions=int(VrtuPermission.READ),
            parent_base=0x8000,
            parent_top=0x9000,
            parent_permissions=int(VrtuPermission.READ | VrtuPermission.WRITE),
        )
        with self.assertRaises(PermissionError):
            vrtu.configure_from_capability(
                1,
                valid=True,
                vbase=0x5000,
                vtop=0x5400,
                pbase=0x8800,
                permissions=int(VrtuPermission.EXECUTE),
                parent_base=0x8000,
                parent_top=0x9000,
                parent_permissions=int(VrtuPermission.READ | VrtuPermission.WRITE),
            )

    def test_configuration_rejects_wx_and_physical_overflow(self) -> None:
        vrtu = Vrtu(1, physical_bits=12)
        with self.assertRaises(ValueError):
            vrtu.configure(
                0,
                valid=True,
                vbase=0,
                vtop=0x100,
                pbase=0,
                permissions=int(VrtuPermission.WRITE | VrtuPermission.EXECUTE),
            )
        with self.assertRaises(ValueError):
            vrtu.configure(
                0,
                valid=True,
                vbase=0,
                vtop=0x200,
                pbase=0xF00,
                permissions=int(VrtuPermission.READ),
            )

    def test_generation_does_not_wrap(self) -> None:
        vrtu = Vrtu(1)
        vrtu.entries[0].generation = 0xFFFF_FFFF
        with self.assertRaises(OverflowError):
            vrtu.configure(
                0,
                valid=True,
                vbase=0,
                vtop=0x100,
                pbase=0,
                permissions=int(VrtuPermission.READ),
            )

    def test_lock_prevents_software_rewrite(self) -> None:
        vrtu = tang138k_nommu_vrtu(performance_profile=True)
        with self.assertRaises(PermissionError):
            vrtu.configure(0, valid=False, vbase=0, vtop=0, pbase=0, permissions=0)


if __name__ == "__main__":
    unittest.main()
