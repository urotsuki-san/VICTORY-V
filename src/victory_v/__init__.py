"""VICTORY-V assembler, executable models, range translation, and profiles."""

from .assembler import AssembledProgram, assemble
from .contract import AdmittedContract, ContractSpec
from .family import (
    ARCHITECTURES,
    DECISION_ENGINES,
    SYSTEM_PROFILES,
    VRTU_PROFILES,
    ArchitectureProfile,
    DecisionEngineProfile,
    SystemProfile,
    VrtuProfile,
)
from .machine import Machine, MachineConfig, RunResult
from .vrtu import Vrtu, VrtuAccess, VrtuCause, VrtuFault, VrtuPermission, VrtuTranslation

__all__ = [
    "ARCHITECTURES",
    "DECISION_ENGINES",
    "SYSTEM_PROFILES",
    "VRTU_PROFILES",
    "AdmittedContract",
    "ArchitectureProfile",
    "AssembledProgram",
    "ContractSpec",
    "DecisionEngineProfile",
    "Machine",
    "MachineConfig",
    "RunResult",
    "SystemProfile",
    "Vrtu",
    "VrtuAccess",
    "VrtuCause",
    "VrtuFault",
    "VrtuPermission",
    "VrtuProfile",
    "VrtuTranslation",
    "assemble",
]
__version__ = "0.7.0a0"
