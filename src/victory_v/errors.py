"""Public exceptions raised by the VICTORY-V tools."""

from __future__ import annotations


class VictoryError(Exception):
    """Base class for user-facing VICTORY-V tool errors."""


class AssemblyError(VictoryError):
    """The source program could not be assembled."""

    def __init__(self, message: str, *, line: int | None = None, source: str | None = None) -> None:
        prefix = f"line {line}: " if line is not None else ""
        suffix = f"\n    {source}" if source else ""
        super().__init__(f"{prefix}{message}{suffix}")
        self.line = line
        self.source = source


class MachineFault(VictoryError):
    """Raised only when the host asks the model to surface a terminal fault."""
