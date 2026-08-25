"""Architecture-family definitions shared by tools and documentation.

VV32-A0 is the implemented source architecture.  VV64-A0 and the Linux
profiles are design contracts; their presence here does not claim that a
64-bit core or kernel port already exists.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Final, Literal

Translation = Literal["none", "optional", "required"]
Status = Literal["implemented-alpha", "design-draft", "planned"]

FAMILY_NAME: Final[str] = "VICTORY-V"
SOURCE_ARCHITECTURE: Final[str] = "VV32-A0"
INSTRUCTION_WIDTH_BITS: Final[int] = 32

FAMILY_RULES: Final[frozenset[str]] = frozenset(
    {
        "capability_checked_memory",
        "monotonic_authority",
        "secret_flow_tracking",
        "bounded_victory_regions",
        "root_lock",
        "explicit_failure",
        "non_speculative_baseline",
    }
)


@dataclass(frozen=True, slots=True)
class ArchitectureProfile:
    name: str
    status: Status
    xlen: int
    address_bits: int
    translation: Translation
    inherits: str | None
    hardware_target: str
    required_rules: frozenset[str]


@dataclass(frozen=True, slots=True)
class SystemProfile:
    name: str
    architecture: str
    status: Status
    mmu: bool
    userspace_abi: str
    virtual_address_bits: int | None


VV32_A0: Final[ArchitectureProfile] = ArchitectureProfile(
    name="VV32-A0",
    status="implemented-alpha",
    xlen=32,
    address_bits=32,
    translation="none",
    inherits=None,
    hardware_target="Tang Nano 20K",
    required_rules=FAMILY_RULES,
)

VV64_A0_RULES: Final[frozenset[str]] = FAMILY_RULES | frozenset(
    {
        "tagged_context",
        "sealed_control_flow",
        "capability_checked_atomics",
        "translation_cannot_add_authority",
        "interrupt_abort_region",
    }
)

VV64_A0: Final[ArchitectureProfile] = ArchitectureProfile(
    name="VV64-A0",
    status="design-draft",
    xlen=64,
    address_bits=64,
    translation="optional",
    inherits="VV32-A0",
    hardware_target="Tang Console 138K",
    required_rules=VV64_A0_RULES,
)

ARCHITECTURES: Final[dict[str, ArchitectureProfile]] = {
    VV32_A0.name: VV32_A0,
    VV64_A0.name: VV64_A0,
}

VV64_L0_FLAT: Final[SystemProfile] = SystemProfile(
    name="VV64-L0-flat",
    architecture="VV64-A0",
    status="planned",
    mmu=False,
    userspace_abi="FDPIC-or-FLAT",
    virtual_address_bits=None,
)

VV64_L0_PAGED: Final[SystemProfile] = SystemProfile(
    name="VV64-L0-paged",
    architecture="VV64-A0",
    status="planned",
    mmu=True,
    userspace_abi="ELF",
    virtual_address_bits=39,
)

SYSTEM_PROFILES: Final[dict[str, SystemProfile]] = {
    VV64_L0_FLAT.name: VV64_L0_FLAT,
    VV64_L0_PAGED.name: VV64_L0_PAGED,
}


def validate_family() -> None:
    source = ARCHITECTURES[SOURCE_ARCHITECTURE]
    if source.inherits is not None:
        raise ValueError("the source architecture cannot inherit another profile")
    if source.required_rules != FAMILY_RULES:
        raise ValueError("VV32-A0 must carry the full family contract")

    for profile in ARCHITECTURES.values():
        if profile.xlen not in {32, 64}:
            raise ValueError(f"unsupported XLEN in {profile.name}: {profile.xlen}")
        if not FAMILY_RULES <= profile.required_rules:
            missing = sorted(FAMILY_RULES - profile.required_rules)
            raise ValueError(f"{profile.name} drops family rules: {missing}")
        if profile.inherits is not None and profile.inherits not in ARCHITECTURES:
            raise ValueError(f"unknown parent for {profile.name}: {profile.inherits}")

    for profile in SYSTEM_PROFILES.values():
        architecture = ARCHITECTURES.get(profile.architecture)
        if architecture is None:
            raise ValueError(f"unknown architecture for {profile.name}: {profile.architecture}")
        if profile.mmu and architecture.translation == "none":
            raise ValueError(f"{profile.name} requests an MMU from a no-translation architecture")
        if profile.mmu != (profile.virtual_address_bits is not None):
            raise ValueError(f"{profile.name} has an inconsistent virtual-address definition")


validate_family()
