"""Executable reference model for the experimental VICTORY-V VV32-A0 ISA."""

from .assembler import AssembledProgram, assemble
from .machine import Machine, MachineConfig, RunResult

__all__ = ["AssembledProgram", "Machine", "MachineConfig", "RunResult", "assemble"]
__version__ = "0.1.0a0"
