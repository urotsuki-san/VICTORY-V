"""Architecture and hardware profiles shared by repository tools."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Final, Literal

Translation = Literal["none", "range", "optional", "required"]
Status = Literal["implemented-alpha", "rtl-alpha", "design-draft", "planned", "experiment"]

FAMILY_NAME: Final[str] = "VICTORY-V"
SOURCE_ARCHITECTURE: Final[str] = "VV32-A0"
INSTRUCTION_WIDTH_BITS: Final[int] = 32

FAMILY_RULES: Final[frozenset[str]] = frozenset(
    {
        "capability_checked_memory",
        "monotonic_authority",
        "secret_flow_tracking",
        "declared_footprint",
        "complete_region_rollback",
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
    protection: str
    userspace_abi: str
    virtual_address_bits: int | None


@dataclass(frozen=True, slots=True)
class VrtuProfile:
    name: str
    entries: int
    address_bits: int
    software_refill: bool
    page_walker: bool
    locked_reset_map: bool


@dataclass(frozen=True, slots=True)
class DecisionEngineProfile:
    name: str
    status: Status
    interface: str
    operation: str
    candidates: int
    dimensions: int
    coordinate_bits: int
    exact_result: bool
    cpu_visible: bool
    hardware_target: str


VV32_A0: Final[ArchitectureProfile] = ArchitectureProfile(
    name="VV32-A0",
    status="implemented-alpha",
    xlen=32,
    address_bits=32,
    translation="none",
    inherits=None,
    hardware_target="Tang Nano 20K / Tang 138K",
    required_rules=FAMILY_RULES,
)

VV64_A0_RULES: Final[frozenset[str]] = FAMILY_RULES | frozenset(
    {
        "generation_checked_capability_directory",
        "translation_cannot_add_authority",
        "interrupt_abort_region",
        "exact_range_translation",
    }
)

VV64_A0: Final[ArchitectureProfile] = ArchitectureProfile(
    name="VV64-A0",
    status="rtl-alpha",
    xlen=64,
    address_bits=64,
    translation="range",
    inherits="VV32-A0",
    hardware_target="Tang 138K",
    required_rules=VV64_A0_RULES,
)

ARCHITECTURES: Final[dict[str, ArchitectureProfile]] = {
    VV32_A0.name: VV32_A0,
    VV64_A0.name: VV64_A0,
}

VV64_L0_FLAT: Final[SystemProfile] = SystemProfile(
    name="VV64-L0-flat",
    architecture="VV64-A0",
    status="rtl-alpha",
    mmu=False,
    protection="VRTU flat range protection",
    userspace_abi="FDPIC-or-FLAT",
    virtual_address_bits=None,
)

VV64_L0_PAGED: Final[SystemProfile] = SystemProfile(
    name="VV64-L0-paged",
    architecture="VV64-A0",
    status="planned",
    mmu=True,
    protection="V39 page translation",
    userspace_abi="ELF",
    virtual_address_bits=39,
)

SYSTEM_PROFILES: Final[dict[str, SystemProfile]] = {
    VV64_L0_FLAT.name: VV64_L0_FLAT,
    VV64_L0_PAGED.name: VV64_L0_PAGED,
}

VRTU_P0: Final[VrtuProfile] = VrtuProfile(
    name="VRTU-P0",
    entries=4,
    address_bits=17,
    software_refill=False,
    page_walker=False,
    locked_reset_map=True,
)
VRTU_E0: Final[VrtuProfile] = VrtuProfile(
    name="VRTU-E0",
    entries=2,
    address_bits=17,
    software_refill=False,
    page_walker=False,
    locked_reset_map=True,
)
VRTU_PROFILES: Final[dict[str, VrtuProfile]] = {
    VRTU_P0.name: VRTU_P0,
    VRTU_E0.name: VRTU_E0,
}

EUCLID_EXPERIMENT: Final[DecisionEngineProfile] = DecisionEngineProfile(
    name="EUCLID-experiment",
    status="experiment",
    interface="archived benchmark",
    operation="exact-squared-euclidean-nearest",
    candidates=4,
    dimensions=8,
    coordinate_bits=8,
    exact_result=True,
    cpu_visible=False,
    hardware_target="experiments/euclid only; not in the FPGA image",
)

DECISION_ENGINES: Final[dict[str, DecisionEngineProfile]] = {
    EUCLID_EXPERIMENT.name: EUCLID_EXPERIMENT,
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

    for profile in VRTU_PROFILES.values():
        if profile.entries < 1 or profile.address_bits < 1:
            raise ValueError(f"invalid VRTU profile: {profile.name}")
        if profile.software_refill or profile.page_walker:
            raise ValueError(f"{profile.name} is no longer the small exact VRTU profile")

    for profile in DECISION_ENGINES.values():
        if profile.status != "experiment" or profile.cpu_visible:
            raise ValueError(f"{profile.name} must remain an isolated experiment")


validate_family()
