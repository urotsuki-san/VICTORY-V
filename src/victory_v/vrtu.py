"""Exact range translation used by the no-MMU VICTORY-V profile."""

from __future__ import annotations

from dataclasses import dataclass
from enum import IntEnum, IntFlag


class VrtuAccess(IntEnum):
    READ = 0
    WRITE = 1
    EXECUTE = 2


class VrtuPermission(IntFlag):
    READ = 1 << 0
    WRITE = 1 << 1
    EXECUTE = 1 << 2
    USER = 1 << 3
    DEVICE = 1 << 4


class VrtuCause(IntEnum):
    MISS = 20
    PERMISSION = 21
    CONFLICT = 22
    DEVICE = 27
    GENERATION_WRAP = 30
    CONFIGURATION = 31


class VrtuFault(RuntimeError):
    def __init__(self, cause: VrtuCause, address: int) -> None:
        super().__init__(f"VRTU {cause.name.lower()} at 0x{address:x}")
        self.cause = cause
        self.address = address


@dataclass(slots=True)
class VrtuDescriptor:
    valid: bool = False
    generation: int = 0
    vbase: int = 0
    vtop: int = 0
    pbase: int = 0
    permissions: int = 0

    def contains(self, address: int, size: int) -> bool:
        end = address + size
        return self.valid and size > 0 and end >= address and self.vbase <= address and end <= self.vtop

    def overlaps(self, vbase: int, vtop: int) -> bool:
        return self.valid and vbase < self.vtop and self.vbase < vtop


@dataclass(frozen=True, slots=True)
class VrtuTranslation:
    physical_address: int
    descriptor_index: int
    permissions: int

    @property
    def device(self) -> bool:
        return bool(self.permissions & int(VrtuPermission.DEVICE))


@dataclass(slots=True)
class _Guard:
    valid: bool = False
    generation: int = 0
    index: int = 0
    vbase: int = 0
    vtop: int = 0
    pbase: int = 0
    permissions: int = 0

    def clear(self) -> None:
        self.valid = False


class Vrtu:
    """Small exact range translator with one guarded-reuse entry per access kind."""

    def __init__(self, entries: int, *, physical_bits: int = 17) -> None:
        if entries < 1:
            raise ValueError("entries must be positive")
        if not 1 <= physical_bits <= 64:
            raise ValueError("physical_bits must be between 1 and 64")
        self.entries = [VrtuDescriptor() for _ in range(entries)]
        self.physical_bits = physical_bits
        self.locked = False
        self._guards = {access: _Guard() for access in VrtuAccess}

    @property
    def physical_limit(self) -> int:
        return 1 << self.physical_bits

    def _validate_descriptor(
        self,
        index: int,
        *,
        valid: bool,
        vbase: int,
        vtop: int,
        pbase: int,
        permissions: int,
        allow_wx: bool = False,
    ) -> None:
        if not 0 <= index < len(self.entries):
            raise IndexError("VRTU descriptor index is out of range")
        if not valid:
            return
        if vbase < 0 or vtop <= vbase or pbase < 0:
            raise ValueError("valid VRTU ranges must be non-empty and non-negative")
        length = vtop - vbase
        if pbase + length > self.physical_limit:
            raise ValueError("VRTU physical range exceeds the implemented address width")
        permissions &= 0x1F
        if (
            not allow_wx
            and permissions & int(VrtuPermission.WRITE)
            and permissions & int(VrtuPermission.EXECUTE)
        ):
            raise ValueError("VRTU descriptors are W^X")
        if permissions & int(VrtuPermission.DEVICE) and permissions & int(VrtuPermission.EXECUTE):
            raise ValueError("device ranges cannot be executable")
        for other_index, descriptor in enumerate(self.entries):
            if other_index != index and descriptor.overlaps(vbase, vtop):
                raise ValueError("VRTU ranges may not overlap")

    def configure(
        self,
        index: int,
        *,
        valid: bool,
        vbase: int,
        vtop: int,
        pbase: int,
        permissions: int,
        allow_wx: bool = False,
    ) -> None:
        if self.locked:
            raise PermissionError("VRTU descriptor bank is locked")
        self._validate_descriptor(
            index,
            valid=valid,
            vbase=vbase,
            vtop=vtop,
            pbase=pbase,
            permissions=permissions,
            allow_wx=allow_wx,
        )
        descriptor = self.entries[index]
        if descriptor.generation == 0xFFFF_FFFF:
            raise OverflowError("VRTU descriptor generation is exhausted")
        descriptor.valid = valid
        descriptor.generation += 1
        descriptor.vbase = vbase
        descriptor.vtop = vtop
        descriptor.pbase = pbase
        descriptor.permissions = permissions & 0x1F
        for guard in self._guards.values():
            guard.clear()

    def configure_from_capability(
        self,
        index: int,
        *,
        valid: bool,
        vbase: int,
        vtop: int,
        pbase: int,
        permissions: int,
        parent_base: int,
        parent_top: int,
        parent_permissions: int,
    ) -> None:
        if valid:
            length = vtop - vbase
            physical_top = pbase + length
            if length <= 0 or pbase < parent_base or physical_top > parent_top:
                raise PermissionError("VRTU range exceeds its parent capability")
            if permissions & ~parent_permissions:
                raise PermissionError("VRTU permissions exceed the parent capability")
        self.configure(
            index,
            valid=valid,
            vbase=vbase,
            vtop=vtop,
            pbase=pbase,
            permissions=permissions,
        )

    def lock(self) -> None:
        self.locked = True

    @staticmethod
    def _required(access: VrtuAccess) -> int:
        return {
            VrtuAccess.READ: int(VrtuPermission.READ),
            VrtuAccess.WRITE: int(VrtuPermission.WRITE),
            VrtuAccess.EXECUTE: int(VrtuPermission.EXECUTE),
        }[access]

    def _check_permission(self, permissions: int, access: VrtuAccess, user: bool) -> bool:
        required = self._required(access)
        return bool(permissions & required) and (not user or bool(permissions & int(VrtuPermission.USER)))

    def _physical(self, pbase: int, vbase: int, address: int, size: int) -> int:
        physical = pbase + (address - vbase)
        if physical < 0 or physical + size > self.physical_limit or physical + size < physical:
            raise VrtuFault(VrtuCause.MISS, address)
        return physical

    def _finish_translation(
        self,
        *,
        index: int,
        vbase: int,
        pbase: int,
        permissions: int,
        address: int,
        size: int,
        access: VrtuAccess,
        user: bool,
        region_active: bool,
    ) -> VrtuTranslation:
        if not self._check_permission(permissions, access, user):
            raise VrtuFault(VrtuCause.PERMISSION, address)
        if region_active and permissions & int(VrtuPermission.DEVICE):
            raise VrtuFault(VrtuCause.DEVICE, address)
        return VrtuTranslation(
            physical_address=self._physical(pbase, vbase, address, size),
            descriptor_index=index,
            permissions=permissions,
        )

    def translate_detail(
        self,
        address: int,
        *,
        size: int,
        access: VrtuAccess,
        user: bool = False,
        region_active: bool = False,
    ) -> VrtuTranslation:
        if address < 0 or size <= 0 or address + size < address:
            raise VrtuFault(VrtuCause.MISS, address)

        guard = self._guards[access]
        if guard.valid:
            descriptor = self.entries[guard.index]
            if (
                descriptor.valid
                and descriptor.generation == guard.generation
                and guard.vbase <= address
                and address + size <= guard.vtop
            ):
                return self._finish_translation(
                    index=guard.index,
                    vbase=guard.vbase,
                    pbase=guard.pbase,
                    permissions=guard.permissions,
                    address=address,
                    size=size,
                    access=access,
                    user=user,
                    region_active=region_active,
                )

        matches = [
            (index, descriptor)
            for index, descriptor in enumerate(self.entries)
            if descriptor.contains(address, size)
        ]
        if not matches:
            raise VrtuFault(VrtuCause.MISS, address)
        if len(matches) != 1:
            raise VrtuFault(VrtuCause.CONFLICT, address)

        index, descriptor = matches[0]
        translation = self._finish_translation(
            index=index,
            vbase=descriptor.vbase,
            pbase=descriptor.pbase,
            permissions=descriptor.permissions,
            address=address,
            size=size,
            access=access,
            user=user,
            region_active=region_active,
        )
        guard.valid = True
        guard.index = index
        guard.generation = descriptor.generation
        guard.vbase = descriptor.vbase
        guard.vtop = descriptor.vtop
        guard.pbase = descriptor.pbase
        guard.permissions = descriptor.permissions
        return translation

    def translate(
        self,
        address: int,
        *,
        size: int,
        access: VrtuAccess,
        user: bool = False,
        region_active: bool = False,
    ) -> int:
        return self.translate_detail(
            address,
            size=size,
            access=access,
            user=user,
            region_active=region_active,
        ).physical_address


def tang138k_nommu_vrtu(*, performance_profile: bool) -> Vrtu:
    """Return the locked reset map used by the first Tang 138K image."""

    vrtu = Vrtu(4 if performance_profile else 2, physical_bits=17)
    vrtu.configure(
        0,
        valid=True,
        vbase=0x00000,
        vtop=0x10000,
        pbase=0x00000,
        permissions=int(
            VrtuPermission.READ
            | VrtuPermission.WRITE
            | VrtuPermission.EXECUTE
            | VrtuPermission.USER
        ),
        allow_wx=True,
    )
    vrtu.configure(
        1,
        valid=True,
        vbase=0x10000,
        vtop=0x20000,
        pbase=0x10000,
        permissions=int(VrtuPermission.READ | VrtuPermission.WRITE | VrtuPermission.DEVICE),
    )
    vrtu.lock()
    return vrtu
