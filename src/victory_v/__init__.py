"""VICTORY-V assembler, reference model, and architecture profiles."""

from .assembler import AssembledProgram, assemble
from .family import ARCHITECTURES, SYSTEM_PROFILES, ArchitectureProfile, SystemProfile
from .machine import Machine, MachineConfig, RunResult

__all__ = [
    "ARCHITECTURES",
    "SYSTEM_PROFILES",
    "ArchitectureProfile",
    "AssembledProgram",
    "Machine",
    "MachineConfig",
    "RunResult",
    "SystemProfile",
    "assemble",
]
__version__ = "0.3.0a0"
