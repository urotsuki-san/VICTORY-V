"""Compact Victory Contract fields used by the A0 cores."""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True, slots=True)
class ContractSpec:
    store_granules: int
    instruction_budget: int
    register_writes: int
    capability_allocations: int = 0
    fixed_release: bool = False
    secret: bool = False
    release_delta: int = 0

    def validate(self) -> None:
        if not 1 <= self.store_granules <= 31:
            raise ValueError("store_granules must be between 1 and 31")
        if not 1 <= self.instruction_budget <= 255:
            raise ValueError("instruction_budget must be between 1 and 255")
        if not 1 <= self.register_writes <= 31:
            raise ValueError("register_writes must be between 1 and 31")
        if not 0 <= self.capability_allocations <= 31:
            raise ValueError("capability_allocations must be between 0 and 31")
        if not 0 <= self.release_delta <= 127:
            raise ValueError("release_delta must be between 0 and 127")
        if self.fixed_release and self.release_delta == 0:
            raise ValueError("fixed_release requires release_delta")
        if self.secret and not self.fixed_release:
            raise ValueError("secret contracts require fixed_release")

    def pack(self) -> int:
        self.validate()
        return (
            self.store_granules
            | (self.instruction_budget << 5)
            | (self.register_writes << 13)
            | (self.capability_allocations << 18)
            | (int(self.fixed_release) << 23)
            | (int(self.secret) << 24)
            | (self.release_delta << 25)
        )

    @classmethod
    def unpack(cls, value: int) -> "ContractSpec":
        value &= 0xFFFF_FFFF
        spec = cls(
            store_granules=value & 0x1F,
            instruction_budget=(value >> 5) & 0xFF,
            register_writes=(value >> 13) & 0x1F,
            capability_allocations=(value >> 18) & 0x1F,
            fixed_release=bool((value >> 23) & 1),
            secret=bool((value >> 24) & 1),
            release_delta=(value >> 25) & 0x7F,
        )
        spec.validate()
        return spec


@dataclass(frozen=True, slots=True)
class AdmittedContract:
    generation: int
    arena_base: int
    arena_top: int
    arena_permissions: int
    spec: ContractSpec

    def contains(self, address: int, size: int) -> bool:
        end = address + size
        return size > 0 and end >= address and self.arena_base <= address and end <= self.arena_top
