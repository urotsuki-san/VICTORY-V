"""Executable reference machine for VICTORY-V VV32-A0."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Iterable

from .assembler import words_from_bytes
from .contract import AdmittedContract, ContractSpec
from .isa import (
    CapabilityPermission,
    Cause,
    Csr,
    DecodedInstruction,
    Opcode,
    decode,
    mask32,
    sign_extend,
    signed32,
)


@dataclass(slots=True)
class Capability:
    valid: bool = False
    base: int = 0
    top: int = 0
    permissions: int = 0

    def copy(self) -> "Capability":
        return Capability(self.valid, self.base, self.top, self.permissions)


@dataclass(slots=True)
class BufferedStore:
    address: int
    data: bytearray = field(default_factory=lambda: bytearray(4))
    mask: int = 0

    def merge(self, address: int, payload: bytes) -> None:
        offset = address - self.address
        if offset < 0 or offset + len(payload) > 4:
            raise ValueError("store crosses a VV32 write-set granule")
        for index, value in enumerate(payload):
            byte_index = offset + index
            self.data[byte_index] = value
            self.mask |= 1 << byte_index

    def overlay(self, address: int, payload: bytearray) -> None:
        for byte_index in range(4):
            absolute = self.address + byte_index
            if self.mask & (1 << byte_index) and address <= absolute < address + len(payload):
                payload[absolute - address] = self.data[byte_index]

    def publish(self, memory: bytearray) -> None:
        for byte_index in range(4):
            if self.mask & (1 << byte_index):
                memory[self.address + byte_index] = self.data[byte_index]


@dataclass(slots=True)
class RegisterSnapshot:
    index: int
    value: int
    capability: Capability
    secret: bool
    contract_generation: int


@dataclass(slots=True)
class VictoryRegion:
    active: bool = False
    fail_pc: int = 0
    store_quota: int = 0
    instruction_budget: int = 0
    instructions_used: int = 0
    register_quota: int = 0
    register_dirty: int = 0
    register_log: list[RegisterSnapshot] = field(default_factory=list)
    register_high_water: int = 0
    capability_quota: int = 0
    capability_used: int = 0
    arena_valid: bool = False
    arena_base: int = 0
    arena_top: int = 0
    fixed_release: bool = False
    secret_mode: bool = False
    release_cycle: int = 0
    stores: list[BufferedStore] = field(default_factory=list)

    def clear(self) -> None:
        self.active = False
        self.fail_pc = 0
        self.store_quota = 0
        self.instruction_budget = 0
        self.instructions_used = 0
        self.register_quota = 0
        self.register_dirty = 0
        self.register_log.clear()
        self.register_high_water = 0
        self.capability_quota = 0
        self.capability_used = 0
        self.arena_valid = False
        self.arena_base = 0
        self.arena_top = 0
        self.fixed_release = False
        self.secret_mode = False
        self.release_cycle = 0
        self.stores.clear()


@dataclass(slots=True)
class PendingRelease:
    kind: str
    release_cycle: int
    fail_pc: int = 0
    error: int = 0


@dataclass(frozen=True, slots=True)
class MachineConfig:
    memory_size: int = 64 * 1024
    region_store_depth: int = 8
    region_register_depth: int = 31
    region_capability_depth: int = 8
    device_base: int | None = None
    device_top: int | None = None
    stop_on_unhandled_trap: bool = True


@dataclass(frozen=True, slots=True)
class TraceEntry:
    cycle: int
    pc: int
    word: int
    note: str


@dataclass(frozen=True, slots=True)
class RunResult:
    halted: bool
    waiting: bool
    faulted: bool
    steps: int
    pc: int
    cause: int
    victory_error: int


class Machine:
    """Deterministic, single-core executable model.

    The model is intentionally stricter than a generic CPU emulator. Every
    data access requires a capability; secret-tagged values cannot control a
    branch or address; and a Victory Region buffers stores until ``VIC``.
    """

    def __init__(self, config: MachineConfig | None = None) -> None:
        self.config = config or MachineConfig()
        if self.config.memory_size <= 0:
            raise ValueError("memory_size must be positive")
        if not 1 <= self.config.region_store_depth <= 31:
            raise ValueError("region_store_depth must be between 1 and 31")
        if not 1 <= self.config.region_register_depth <= 31:
            raise ValueError("region_register_depth must be between 1 and 31")
        if not 0 <= self.config.region_capability_depth <= 31:
            raise ValueError("region_capability_depth must be between 0 and 31")
        if (self.config.device_base is None) != (self.config.device_top is None):
            raise ValueError("device_base and device_top must be set together")
        if self.config.device_base is not None:
            if not 0 <= self.config.device_base < self.config.device_top <= self.config.memory_size:
                raise ValueError("device range must be non-empty and inside model memory")
        self.memory = bytearray(self.config.memory_size)
        self.program: tuple[int, ...] = ()
        self.trace: list[TraceEntry] = []
        self.reset(clear_memory=False)

    def reset(self, *, clear_memory: bool = True) -> None:
        if clear_memory:
            self.memory[:] = b"\x00" * len(self.memory)
        self.registers = [0] * 32
        self.capabilities = [Capability() for _ in range(32)]
        self.secret_tags = [False] * 32
        self.contract_token_tags = [0] * 32
        self.contract_generation = 0
        self.admitted_contract: AdmittedContract | None = None
        self.pending_release: PendingRelease | None = None
        self.pc = 0
        self.current_pc = 0
        self.halted = False
        self.waiting = False
        self.faulted = False
        self.pending_interrupt = False
        self.interrupt_enabled = False
        self.root_locked = False
        self.vtvec = 0
        self.vepc = 0
        self.vcause = int(Cause.NONE)
        self.vbadaddr = 0
        self.v_error = 0
        self.cycle = 0
        self.instret = 0
        self.region = VictoryRegion()
        self.last_register_high_water = 0
        self.trace.clear()

    def load_program(self, words: Iterable[int], *, reset: bool = True) -> None:
        self.program = tuple(word & 0xFFFF_FFFF for word in words)
        if reset:
            self.reset(clear_memory=True)

    def load_program_bytes(self, data: bytes, *, reset: bool = True) -> None:
        self.load_program(words_from_bytes(data), reset=reset)

    def request_interrupt(self) -> None:
        self.pending_interrupt = True
        self.waiting = False

    def read_memory(self, address: int, size: int) -> bytes:
        self._validate_host_range(address, size)
        return bytes(self.memory[address : address + size])

    def write_memory(self, address: int, payload: bytes) -> None:
        self._validate_host_range(address, len(payload))
        self.memory[address : address + len(payload)] = payload

    def read_u32(self, address: int) -> int:
        return int.from_bytes(self.read_memory(address, 4), "little")

    def write_u32(self, address: int, value: int) -> None:
        self.write_memory(address, mask32(value).to_bytes(4, "little"))

    def _validate_host_range(self, address: int, size: int) -> None:
        if address < 0 or size < 0 or address + size > len(self.memory):
            raise ValueError(f"memory range outside model: 0x{address:08x}+{size}")

    def _log_register(self, index: int) -> bool:
        if index == 0 or not self.region.active:
            return True
        bit = 1 << index
        if self.region.register_dirty & bit:
            return True
        if len(self.region.register_log) >= self.region.register_quota:
            self._abort_region(int(Cause.REGION_REG_QUOTA))
            return False
        self.region.register_log.append(
            RegisterSnapshot(
                index=index,
                value=self.registers[index],
                capability=self.capabilities[index].copy(),
                secret=self.secret_tags[index],
                contract_generation=self.contract_token_tags[index],
            )
        )
        self.region.register_dirty |= bit
        self.region.register_high_water = max(
            self.region.register_high_water, len(self.region.register_log)
        )
        return True

    def _write_integer(self, rd: int, value: int, *, secret: bool = False) -> bool:
        if rd == 0:
            return True
        if not self._log_register(rd):
            return False
        self.registers[rd] = mask32(value)
        self.capabilities[rd] = Capability()
        self.secret_tags[rd] = bool(secret)
        self.contract_token_tags[rd] = 0
        return True

    def _write_copy(self, rd: int, rs: int) -> bool:
        if rd == 0:
            return True
        if not self._log_register(rd):
            return False
        self.registers[rd] = self.registers[rs]
        self.capabilities[rd] = self.capabilities[rs].copy()
        self.secret_tags[rd] = self.secret_tags[rs]
        self.contract_token_tags[rd] = self.contract_token_tags[rs]
        return True

    def _write_capability(
        self,
        rd: int,
        *,
        cursor: int,
        base: int,
        top: int,
        permissions: int,
    ) -> bool:
        if rd == 0:
            return True
        if not self._log_register(rd):
            return False
        self.registers[rd] = mask32(cursor)
        self.capabilities[rd] = Capability(True, mask32(base), mask32(top), permissions & 0x1F)
        self.secret_tags[rd] = False
        self.contract_token_tags[rd] = 0
        return True

    def _write_contract_token(self, rd: int, generation: int) -> bool:
        if rd == 0:
            return False
        if not self._log_register(rd):
            return False
        self.registers[rd] = mask32(generation)
        self.capabilities[rd] = Capability()
        self.secret_tags[rd] = False
        self.contract_token_tags[rd] = mask32(generation)
        return True

    def _enforce_r0(self) -> None:
        self.registers[0] = 0
        self.capabilities[0] = Capability()
        self.secret_tags[0] = False
        self.contract_token_tags[0] = 0

    def _scrub_secret_registers(self) -> None:
        for index in range(1, 32):
            if self.secret_tags[index]:
                self.registers[index] = 0
                self.capabilities[index] = Capability()
                self.secret_tags[index] = False

    def _take_trap(
        self, cause: int, *, badaddr: int = 0, return_pc: int | None = None
    ) -> None:
        self.vcause = int(cause) & 0xFFFF_FFFF
        self.vbadaddr = mask32(badaddr)
        self.vepc = mask32(self.current_pc if return_pc is None else return_pc)
        self.interrupt_enabled = False
        self.waiting = False
        if self.vtvec & 0x3:
            self.faulted = True
            self.halted = True
            return
        self.pc = mask32(self.vtvec)
        if self.config.stop_on_unhandled_trap and self.vtvec == 0:
            self.faulted = True
            self.halted = True

    def _restore_region_state(self) -> int:
        high_water = self.region.register_high_water
        for snapshot in reversed(tuple(self.region.register_log)):
            self.registers[snapshot.index] = snapshot.value
            self.capabilities[snapshot.index] = snapshot.capability.copy()
            self.secret_tags[snapshot.index] = snapshot.secret
            self.contract_token_tags[snapshot.index] = snapshot.contract_generation
        return high_water

    def _abort_region(self, error: int, *, interrupt: bool = False) -> None:
        fail_pc = self.region.fail_pc
        release_cycle = self.region.release_cycle
        fixed_release = self.region.fixed_release
        high_water = self._restore_region_state()
        self.region.clear()
        self.last_register_high_water = high_water
        self._enforce_r0()
        if fixed_release and self.cycle < release_cycle:
            self.pending_release = PendingRelease(
                kind="interrupt" if interrupt else "abort",
                release_cycle=release_cycle,
                fail_pc=fail_pc,
                error=int(error) & 0xFFFF_FFFF,
            )
            return
        self.v_error = int(error) & 0xFFFF_FFFF
        self.pc = mask32(fail_pc)
        if interrupt:
            self._take_trap(Cause.INTERRUPT, return_pc=fail_pc)

    def _fault(self, cause: Cause | int, *, badaddr: int = 0) -> None:
        if self.region.active:
            self._abort_region(int(cause))
        else:
            self._take_trap(int(cause), badaddr=badaddr)

    def _is_device_range(self, address: int, size: int) -> bool:
        if self.config.device_base is None or self.config.device_top is None:
            return False
        end = address + size
        return end > self.config.device_base and address < self.config.device_top

    def _begin_region(
        self,
        *,
        fail_pc: int,
        store_quota: int,
        instruction_budget: int,
        register_quota: int,
        capability_quota: int,
        contract: AdmittedContract | None = None,
    ) -> None:
        self.region.active = True
        self.region.fail_pc = mask32(fail_pc)
        self.region.store_quota = store_quota
        self.region.instruction_budget = instruction_budget
        self.region.instructions_used = 0
        self.region.register_quota = register_quota
        self.region.register_dirty = 0
        self.region.register_log.clear()
        self.region.register_high_water = 0
        self.region.capability_quota = capability_quota
        self.region.capability_used = 0
        self.region.stores.clear()
        if contract is None:
            self.region.arena_valid = False
            self.region.arena_base = 0
            self.region.arena_top = 0
            self.region.fixed_release = False
            self.region.secret_mode = False
            self.region.release_cycle = 0
        else:
            self.region.arena_valid = True
            self.region.arena_base = contract.arena_base
            self.region.arena_top = contract.arena_top
            self.region.fixed_release = contract.spec.fixed_release
            self.region.secret_mode = contract.spec.secret
            self.region.release_cycle = mask32(self.cycle + contract.spec.release_delta)
        self.v_error = 0

    def _consume_capability_allocation(self) -> bool:
        if not self.region.active:
            return True
        if self.region.capability_used >= self.region.capability_quota:
            self._abort_region(int(Cause.REGION_CAP_QUOTA))
            return False
        self.region.capability_used += 1
        return True

    def _preflight_commit(self) -> bool:
        for entry in self.region.stores:
            for byte_index in range(4):
                if not entry.mask & (1 << byte_index):
                    continue
                address = entry.address + byte_index
                if address < 0 or address >= len(self.memory):
                    self._abort_region(int(Cause.MEMORY_RANGE))
                    return False
                if self._is_device_range(address, 1):
                    self._abort_region(int(Cause.REGION_DEVICE))
                    return False
        return True

    def _publish_region(self) -> None:
        for entry in self.region.stores:
            entry.publish(self.memory)
        self.last_register_high_water = self.region.register_high_water
        self.region.clear()
        self.v_error = 0

    def _finish_pending_release(self) -> None:
        pending = self.pending_release
        if pending is None:
            return
        self.pending_release = None
        if pending.kind == "commit":
            if self.region.active and self._preflight_commit():
                self._publish_region()
            return
        self.v_error = pending.error
        self.pc = mask32(pending.fail_pc)
        if pending.kind == "interrupt":
            self._take_trap(Cause.INTERRUPT, return_pc=pending.fail_pc)

    def _read_csr(self, csr: int) -> int:
        if csr == int(Csr.VSTATUS):
            return (
                (1 if self.interrupt_enabled else 0)
                | ((1 if self.root_locked else 0) << 1)
                | ((1 if self.region.active else 0) << 2)
            )
        if csr == int(Csr.VTVEC):
            return self.vtvec
        if csr == int(Csr.VEPC):
            return self.vepc
        if csr == int(Csr.VCAUSE):
            return self.vcause
        if csr == int(Csr.VBADADDR):
            return self.vbadaddr
        if csr == int(Csr.VCYCLE):
            return self.cycle & 0xFFFF_FFFF
        if csr == int(Csr.VINSTRET):
            return self.instret & 0xFFFF_FFFF
        if csr == int(Csr.VERROR):
            return self.v_error
        if csr == int(Csr.VREGION_COUNT):
            return len(self.region.stores)
        if csr == int(Csr.VREGION_LIMIT):
            return self.region.instruction_budget
        if csr == int(Csr.VCONTRACT):
            return self.admitted_contract.generation if self.admitted_contract is not None else 0
        if csr == int(Csr.VRELEASE):
            if self.pending_release is not None:
                return self.pending_release.release_cycle & 0xFFFF_FFFF
            return self.region.release_cycle & 0xFFFF_FFFF
        if csr == int(Csr.VREGION_CAPS):
            return ((self.region.capability_quota & 0x1F) << 8) | (self.region.capability_used & 0x1F)
        return 0

    def _write_csr(self, csr: int, value: int) -> None:
        value = mask32(value)
        if csr == int(Csr.VSTATUS):
            self.interrupt_enabled = bool(value & 1)
        elif csr == int(Csr.VTVEC):
            if value & 0x3:
                self._fault(Cause.INSTRUCTION_ALIGNMENT, badaddr=value)
            else:
                self.vtvec = value
        elif csr == int(Csr.VEPC):
            self.vepc = value
        elif csr == int(Csr.VERROR):
            self.v_error = value
        # Other CSRs are read-only in A0.

    def _memory_payload(self, address: int, size: int) -> bytes:
        payload = bytearray(self.memory[address : address + size])
        if self.region.active:
            for entry in self.region.stores:
                entry.overlay(address, payload)
        return bytes(payload)

    def _effective_address(self, cap_index: int, imm16: int, size: int, permission: int) -> int | None:
        if self.secret_tags[cap_index]:
            self._fault(Cause.SECRET_FLOW)
            return None
        capability = self.capabilities[cap_index]
        if not capability.valid:
            self._fault(Cause.CAPABILITY_TAG)
            return None
        if not capability.permissions & permission:
            self._fault(Cause.CAPABILITY_PERMISSION)
            return None
        address = self.registers[cap_index] + sign_extend(imm16, 16)
        if address < 0 or address > 0xFFFF_FFFF:
            self._fault(Cause.CAPABILITY_BOUNDS, badaddr=address)
            return None
        end = address + size
        if address < capability.base or end > capability.top or end < address:
            self._fault(Cause.CAPABILITY_BOUNDS, badaddr=address)
            return None
        if self.region.active and self.region.arena_valid:
            if address < self.region.arena_base or end > self.region.arena_top:
                self._abort_region(int(Cause.REGION_ARENA))
                return None
        if end > len(self.memory):
            self._fault(Cause.MEMORY_RANGE, badaddr=address)
            return None
        if (size == 2 and address & 1) or (size == 4 and address & 3):
            self._fault(Cause.DATA_ALIGNMENT, badaddr=address)
            return None
        return address

    def _load(self, insn: DecodedInstruction, *, size: int, signed: bool) -> None:
        address = self._effective_address(insn.rs1, insn.imm16, size, int(CapabilityPermission.READ))
        if address is None:
            return
        if self.region.active and self._is_device_range(address, size):
            self._abort_region(int(Cause.REGION_DEVICE))
            return
        raw = int.from_bytes(self._memory_payload(address, size), "little")
        if signed:
            raw = sign_extend(raw, size * 8)
        secret = bool(self.capabilities[insn.rs1].permissions & int(CapabilityPermission.SECRET))
        self._write_integer(insn.rd, raw, secret=secret)

    def _buffer_store(self, address: int, payload: bytes) -> bool:
        aligned = address & ~0x3
        for entry in self.region.stores:
            if entry.address == aligned:
                entry.merge(address, payload)
                return True
        if len(self.region.stores) >= self.region.store_quota:
            self._abort_region(int(Cause.REGION_STORE_QUOTA))
            return False
        entry = BufferedStore(aligned)
        entry.merge(address, payload)
        self.region.stores.append(entry)
        return True

    def _store(self, insn: DecodedInstruction, *, size: int) -> None:
        address = self._effective_address(insn.rs1, insn.imm16, size, int(CapabilityPermission.WRITE))
        if address is None:
            return
        if self.region.active and self._is_device_range(address, size):
            self._abort_region(int(Cause.REGION_DEVICE))
            return
        capability = self.capabilities[insn.rs1]
        if self.secret_tags[insn.rd] and not capability.permissions & int(CapabilityPermission.SECRET):
            self._fault(Cause.SECRET_FLOW, badaddr=address)
            return
        payload = (self.registers[insn.rd] & ((1 << (size * 8)) - 1)).to_bytes(size, "little")
        if self.region.active:
            self._buffer_store(address, payload)
        else:
            self.memory[address : address + size] = payload

    def _copy_capability(self, rd: int, rs: int, *, cursor: int | None = None, permissions: int | None = None,
                         base: int | None = None, top: int | None = None) -> None:
        source = self.capabilities[rs]
        self._write_capability(
            rd,
            cursor=self.registers[rs] if cursor is None else cursor,
            base=source.base if base is None else base,
            top=source.top if top is None else top,
            permissions=source.permissions if permissions is None else permissions,
        )

    def _check_cap_source(self, rs: int) -> Capability | None:
        if not self.capabilities[rs].valid:
            self._fault(Cause.CAPABILITY_TAG)
            return None
        if self.secret_tags[rs]:
            self._fault(Cause.SECRET_FLOW)
            return None
        return self.capabilities[rs]

    def _contract_token_live(self, register_index: int) -> bool:
        contract = self.admitted_contract
        return (
            contract is not None
            and self.contract_token_tags[register_index] != 0
            and self.contract_token_tags[register_index] == contract.generation
        )

    def _prepare_contract(self, destination: int, arena_register: int, spec_register: int) -> None:
        if destination == 0 or self.admitted_contract is not None:
            self._fault(Cause.CONTRACT_ADMISSION)
            return
        arena = self._check_cap_source(arena_register)
        if arena is None:
            return
        if self.secret_tags[spec_register] or self.capabilities[spec_register].valid:
            self._fault(Cause.CONTRACT_ADMISSION)
            return
        try:
            spec = ContractSpec.unpack(self.registers[spec_register])
        except ValueError:
            self._fault(Cause.CONTRACT_ADMISSION)
            return
        if (
            spec.store_granules > self.config.region_store_depth
            or spec.register_writes > self.config.region_register_depth
            or spec.capability_allocations > self.config.region_capability_depth
        ):
            self._fault(Cause.CONTRACT_ADMISSION)
            return
        if not arena.valid or arena.top <= arena.base:
            self._fault(Cause.CONTRACT_ADMISSION)
            return
        generation = (self.contract_generation + 1) & 0xFFFF_FFFF
        if generation == 0:
            self._fault(Cause.CAPABILITY_GENERATION_WRAP)
            return
        contract = AdmittedContract(
            generation=generation,
            arena_base=arena.base,
            arena_top=arena.top,
            arena_permissions=arena.permissions,
            spec=spec,
        )
        if not self._write_contract_token(destination, generation):
            self._fault(Cause.CONTRACT_ADMISSION)
            return
        self.contract_generation = generation
        self.admitted_contract = contract

    def _execute(self, insn: DecodedInstruction, next_pc: int) -> None:
        opcode = insn.opcode
        regs = self.registers
        sec = self.secret_tags

        if opcode == Opcode.NOP:
            return
        if opcode == Opcode.MOV:
            self._write_copy(insn.rd, insn.rs1)
            return
        if opcode == Opcode.MOVI:
            self._write_integer(insn.rd, sign_extend(insn.imm16, 16))
            return
        if opcode == Opcode.LUI:
            self._write_integer(insn.rd, insn.imm16 << 16)
            return
        if opcode == Opcode.ADD:
            self._write_integer(insn.rd, regs[insn.rs1] + regs[insn.rs2], secret=sec[insn.rs1] or sec[insn.rs2])
            return
        if opcode == Opcode.ADDI:
            self._write_integer(insn.rd, regs[insn.rs1] + sign_extend(insn.imm16, 16), secret=sec[insn.rs1])
            return
        if opcode == Opcode.SUB:
            self._write_integer(insn.rd, regs[insn.rs1] - regs[insn.rs2], secret=sec[insn.rs1] or sec[insn.rs2])
            return
        if opcode == Opcode.MUL:
            self._write_integer(insn.rd, regs[insn.rs1] * regs[insn.rs2], secret=sec[insn.rs1] or sec[insn.rs2])
            return
        if opcode == Opcode.AND:
            self._write_integer(insn.rd, regs[insn.rs1] & regs[insn.rs2], secret=sec[insn.rs1] or sec[insn.rs2])
            return
        if opcode == Opcode.ANDI:
            self._write_integer(insn.rd, regs[insn.rs1] & insn.imm16, secret=sec[insn.rs1])
            return
        if opcode == Opcode.OR:
            self._write_integer(insn.rd, regs[insn.rs1] | regs[insn.rs2], secret=sec[insn.rs1] or sec[insn.rs2])
            return
        if opcode == Opcode.ORI:
            self._write_integer(insn.rd, regs[insn.rs1] | insn.imm16, secret=sec[insn.rs1])
            return
        if opcode == Opcode.XOR:
            self._write_integer(insn.rd, regs[insn.rs1] ^ regs[insn.rs2], secret=sec[insn.rs1] or sec[insn.rs2])
            return
        if opcode == Opcode.XORI:
            self._write_integer(insn.rd, regs[insn.rs1] ^ insn.imm16, secret=sec[insn.rs1])
            return
        if opcode == Opcode.SHL:
            self._write_integer(insn.rd, regs[insn.rs1] << (regs[insn.rs2] & 31), secret=sec[insn.rs1] or sec[insn.rs2])
            return
        if opcode == Opcode.SHR:
            self._write_integer(insn.rd, regs[insn.rs1] >> (regs[insn.rs2] & 31), secret=sec[insn.rs1] or sec[insn.rs2])
            return
        if opcode == Opcode.SAR:
            self._write_integer(insn.rd, signed32(regs[insn.rs1]) >> (regs[insn.rs2] & 31), secret=sec[insn.rs1] or sec[insn.rs2])
            return
        if opcode == Opcode.CMPEQ:
            self._write_integer(insn.rd, int(regs[insn.rs1] == regs[insn.rs2]), secret=sec[insn.rs1] or sec[insn.rs2])
            return
        if opcode == Opcode.CMPLT:
            self._write_integer(insn.rd, int(signed32(regs[insn.rs1]) < signed32(regs[insn.rs2])), secret=sec[insn.rs1] or sec[insn.rs2])
            return
        if opcode == Opcode.CMPULT:
            self._write_integer(insn.rd, int(regs[insn.rs1] < regs[insn.rs2]), secret=sec[insn.rs1] or sec[insn.rs2])
            return

        if opcode in {Opcode.BRZ, Opcode.BRNZ}:
            if sec[insn.rs1]:
                self._fault(Cause.SECRET_FLOW)
                return
            taken = regs[insn.rs1] == 0 if opcode == Opcode.BRZ else regs[insn.rs1] != 0
            if taken:
                self.pc = mask32(next_pc + insn.off21 * 4)
            return
        if opcode == Opcode.JAL:
            if self._write_integer(insn.rd, next_pc):
                self.pc = mask32(next_pc + insn.off21 * 4)
            return
        if opcode == Opcode.JALR:
            if sec[insn.rs1]:
                self._fault(Cause.SECRET_FLOW)
                return
            target = mask32(regs[insn.rs1] + sign_extend(insn.imm16, 16))
            if target & 0x3:
                self._fault(Cause.INSTRUCTION_ALIGNMENT, badaddr=target)
                return
            if self._write_integer(insn.rd, next_pc):
                self.pc = target
            return
        if opcode == Opcode.HALT:
            if self.region.active:
                self._abort_region(int(Cause.REGION_REQUIRED))
            else:
                self.halted = True
            return
        if opcode == Opcode.TRAP:
            self._fault(Cause.EXPLICIT_TRAP, badaddr=insn.imm16)
            return
        if opcode == Opcode.CSRR:
            self._write_integer(insn.rd, self._read_csr(insn.imm16))
            return
        if opcode == Opcode.CSRW:
            if self.region.active:
                self._abort_region(int(Cause.REGION_REQUIRED))
                return
            if sec[insn.rs1]:
                self._fault(Cause.SECRET_FLOW)
                return
            self._write_csr(insn.imm16, regs[insn.rs1])
            return
        if opcode == Opcode.EI:
            if self.region.active:
                self._abort_region(int(Cause.REGION_REQUIRED))
            else:
                self.interrupt_enabled = True
            return
        if opcode == Opcode.DI:
            if self.region.active:
                self._abort_region(int(Cause.REGION_REQUIRED))
            else:
                self.interrupt_enabled = False
            return
        if opcode == Opcode.VRET:
            if self.region.active:
                self._abort_region(int(Cause.REGION_REQUIRED))
                return
            if self.vepc & 0x3:
                self._fault(Cause.INSTRUCTION_ALIGNMENT, badaddr=self.vepc)
                return
            self.pc = self.vepc
            self.interrupt_enabled = True
            return

        if opcode == Opcode.CROOT:
            if self.region.active:
                self._abort_region(int(Cause.REGION_REQUIRED))
                return
            if self.root_locked:
                self._fault(Cause.ROOT_LOCKED)
                return
            if sec[insn.rs1] or sec[insn.rs2]:
                self._fault(Cause.SECRET_FLOW)
                return
            base = regs[insn.rs1]
            length = regs[insn.rs2]
            top = base + length
            if length == 0 or top > len(self.memory) or top > 0xFFFF_FFFF or top < base:
                self._fault(Cause.CAPABILITY_BOUNDS, badaddr=base)
                return
            self._write_capability(insn.rd, cursor=base, base=base, top=top, permissions=insn.aux & 0x1F)
            return
        if opcode == Opcode.CBOUNDS:
            source = self._check_cap_source(insn.rs1)
            if source is None:
                return
            if sec[insn.rs2]:
                self._fault(Cause.SECRET_FLOW)
                return
            base = regs[insn.rs1]
            top = base + regs[insn.rs2]
            if top < base or base < source.base or top > source.top:
                self._fault(Cause.CAPABILITY_BOUNDS, badaddr=base)
                return
            if not self._consume_capability_allocation():
                return
            self._copy_capability(insn.rd, insn.rs1, base=base, top=top)
            return
        if opcode == Opcode.CPERM:
            source = self._check_cap_source(insn.rs1)
            if source is None:
                return
            if sec[insn.rs2]:
                self._fault(Cause.SECRET_FLOW)
                return
            if not self._consume_capability_allocation():
                return
            self._copy_capability(insn.rd, insn.rs1, permissions=source.permissions & regs[insn.rs2] & 0x1F)
            return
        if opcode == Opcode.CINC:
            source = self._check_cap_source(insn.rs1)
            if source is None:
                return
            if sec[insn.rs2]:
                self._fault(Cause.SECRET_FLOW)
                return
            cursor = regs[insn.rs1] + signed32(regs[insn.rs2])
            if cursor < source.base or cursor > source.top or cursor < 0 or cursor > 0xFFFF_FFFF:
                self._fault(Cause.CAPABILITY_BOUNDS, badaddr=cursor)
                return
            self._copy_capability(insn.rd, insn.rs1, cursor=cursor)
            return
        if opcode == Opcode.CGETTAG:
            self._write_integer(insn.rd, int(self.capabilities[insn.rs1].valid))
            return
        if opcode == Opcode.CGETPERM:
            permissions = self.capabilities[insn.rs1].permissions if self.capabilities[insn.rs1].valid else 0
            self._write_integer(insn.rd, permissions)
            return
        if opcode == Opcode.CLDB:
            self._load(insn, size=1, signed=True)
            return
        if opcode == Opcode.CLDBU:
            self._load(insn, size=1, signed=False)
            return
        if opcode == Opcode.CLDH:
            self._load(insn, size=2, signed=True)
            return
        if opcode == Opcode.CLDHU:
            self._load(insn, size=2, signed=False)
            return
        if opcode == Opcode.CLDW:
            self._load(insn, size=4, signed=False)
            return
        if opcode == Opcode.CSTB:
            self._store(insn, size=1)
            return
        if opcode == Opcode.CSTH:
            self._store(insn, size=2)
            return
        if opcode == Opcode.CSTW:
            self._store(insn, size=4)
            return
        if opcode == Opcode.VDECLASS:
            authority = self.capabilities[insn.rs2]
            if not authority.valid or not authority.permissions & int(CapabilityPermission.DECLASSIFY):
                self._fault(Cause.DECLASSIFY_DENIED)
                return
            self._write_integer(insn.rd, regs[insn.rs1], secret=False)
            return
        if opcode == Opcode.VLOCK:
            if self.region.active:
                self._abort_region(int(Cause.REGION_REQUIRED))
            else:
                self.root_locked = True
            return

        if opcode == Opcode.VPREP:
            if self.region.active:
                self._abort_region(int(Cause.REGION_REQUIRED))
                return
            self._prepare_contract(insn.rd, insn.rs1, insn.rs2)
            return
        if opcode == Opcode.VTRYC:
            if self.region.active:
                self._abort_region(int(Cause.REGION_NESTED))
                return
            if not self._contract_token_live(insn.rs1):
                self._fault(Cause.CONTRACT_TOKEN)
                return
            contract = self.admitted_contract
            assert contract is not None
            self.admitted_contract = None
            self._begin_region(
                fail_pc=mask32(next_pc + insn.off21 * 4),
                store_quota=contract.spec.store_granules,
                instruction_budget=contract.spec.instruction_budget,
                register_quota=contract.spec.register_writes,
                capability_quota=contract.spec.capability_allocations,
                contract=contract,
            )
            return
        if opcode == Opcode.VCANCEL:
            if self.region.active:
                self._abort_region(int(Cause.REGION_REQUIRED))
                return
            if not self._contract_token_live(insn.rs1):
                self._fault(Cause.CONTRACT_TOKEN)
                return
            self.admitted_contract = None
            self.contract_token_tags[insn.rs1] = 0
            return
        if opcode == Opcode.VTRY:
            if self.region.active:
                self._abort_region(int(Cause.REGION_NESTED))
                return
            if (
                insn.stores == 0
                or insn.budget == 0
                or insn.stores > self.config.region_store_depth
                or self.config.region_register_depth < 31
            ):
                self._fault(Cause.CONTRACT_ADMISSION)
                return
            self._begin_region(
                fail_pc=mask32(next_pc + insn.off13 * 4),
                store_quota=insn.stores,
                instruction_budget=insn.budget,
                register_quota=31,
                capability_quota=0,
            )
            return
        if opcode == Opcode.VCHK:
            if not self.region.active:
                self._fault(Cause.REGION_REQUIRED)
                return
            if sec[insn.rs1]:
                self._abort_region(int(Cause.SECRET_FLOW))
                return
            if regs[insn.rs1] == 0:
                self._abort_region(insn.imm16 or int(Cause.EXPLICIT_TRAP))
            return
        if opcode == Opcode.VIC:
            if not self.region.active:
                self._fault(Cause.REGION_REQUIRED)
                return
            if not self._preflight_commit():
                return
            if self.region.fixed_release and self.cycle < self.region.release_cycle:
                self.pending_release = PendingRelease(
                    kind="commit",
                    release_cycle=self.region.release_cycle,
                )
            else:
                self._publish_region()
            return
        if opcode == Opcode.VABT:
            if not self.region.active:
                self._fault(Cause.REGION_REQUIRED)
                return
            self._abort_region(insn.imm16 or int(Cause.EXPLICIT_TRAP))
            return
        if opcode == Opcode.VERR:
            self._write_integer(insn.rd, self.v_error)
            return
        if opcode == Opcode.WFI:
            if self.region.active:
                self._abort_region(int(Cause.REGION_REQUIRED))
            else:
                self.waiting = True
            return

        self._fault(Cause.ILLEGAL_INSTRUCTION)

    def step(self, *, trace: bool = False) -> bool:
        """Execute one instruction or one interrupt transition.

        Returns ``False`` when the machine cannot make progress because it is
        halted, faulted, or waiting without a pending interrupt.
        """

        if self.halted or self.faulted:
            return False
        if self.pending_release is not None:
            self.cycle += 1
            if self.cycle >= self.pending_release.release_cycle:
                self._finish_pending_release()
            return not (self.halted or self.faulted)
        if self.waiting and not self.pending_interrupt:
            return False

        if self.pending_interrupt and self.interrupt_enabled:
            self.current_pc = self.pc
            self.pending_interrupt = False
            self.cycle += 1
            if self.region.active:
                self._abort_region(int(Cause.REGION_PREEMPTED), interrupt=True)
            else:
                self._take_trap(Cause.INTERRUPT, return_pc=self.pc)
            return not (self.halted or self.faulted)

        if self.pc & 0x3:
            self.current_pc = self.pc
            self.cycle += 1
            self._fault(Cause.INSTRUCTION_ALIGNMENT, badaddr=self.pc)
            return not (self.halted or self.faulted)

        index = self.pc // 4
        if index < 0 or index >= len(self.program):
            self.current_pc = self.pc
            self.cycle += 1
            self._fault(Cause.ILLEGAL_INSTRUCTION, badaddr=self.pc)
            return not (self.halted or self.faulted)

        if self.region.active and self.region.instructions_used >= self.region.instruction_budget:
            self.current_pc = self.pc
            self.cycle += 1
            self._abort_region(int(Cause.REGION_BUDGET))
            return True

        self.current_pc = self.pc
        word = self.program[index]
        next_pc = mask32(self.pc + 4)
        self.pc = next_pc
        self.cycle += 1
        if self.region.active:
            self.region.instructions_used += 1

        try:
            insn = decode(word)
        except ValueError:
            self._fault(Cause.ILLEGAL_INSTRUCTION)
            return not (self.halted or self.faulted)

        if trace:
            self.trace.append(TraceEntry(self.cycle, self.current_pc, word, insn.opcode.name.lower()))

        self._execute(insn, next_pc)
        self.instret += 1
        self._enforce_r0()
        return not (self.halted or self.faulted or (self.waiting and not self.pending_interrupt))

    def run(self, *, max_steps: int = 100_000, trace: bool = False) -> RunResult:
        if max_steps <= 0:
            raise ValueError("max_steps must be positive")
        steps = 0
        while steps < max_steps and self.step(trace=trace):
            steps += 1
        # Account for a final instruction that halted or entered WFI.
        if steps < max_steps and (self.halted or self.faulted or self.waiting):
            steps += 1
        return RunResult(
            halted=self.halted,
            waiting=self.waiting,
            faulted=self.faulted,
            steps=steps,
            pc=self.pc,
            cause=self.vcause,
            victory_error=self.v_error,
        )
