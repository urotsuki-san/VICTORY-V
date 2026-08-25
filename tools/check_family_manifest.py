#!/usr/bin/env python3
"""Check that the JSON family contract matches the Python profiles."""

from __future__ import annotations

import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from victory_v.family import (  # noqa: E402
    ARCHITECTURES,
    FAMILY_NAME,
    FAMILY_RULES,
    INSTRUCTION_WIDTH_BITS,
    SOURCE_ARCHITECTURE,
    SYSTEM_PROFILES,
)


def fail(message: str) -> None:
    print(f"family manifest error: {message}", file=sys.stderr)
    raise SystemExit(1)


def main() -> int:
    manifest = json.loads((ROOT / "isa" / "victory-v-family.json").read_text(encoding="utf-8"))
    if manifest.get("family") != FAMILY_NAME:
        fail("family name differs from Python")
    if manifest.get("source_architecture") != SOURCE_ARCHITECTURE:
        fail("source architecture differs from Python")
    if int(manifest.get("instruction_width_bits", 0)) != INSTRUCTION_WIDTH_BITS:
        fail("instruction width differs from Python")
    if set(manifest.get("family_rules", [])) != set(FAMILY_RULES):
        fail("family rules differ from Python")

    json_architectures = manifest.get("architectures", {})
    if set(json_architectures) != set(ARCHITECTURES):
        fail("architecture names differ from Python")
    for name, profile in ARCHITECTURES.items():
        entry = json_architectures[name]
        expected = {
            "status": profile.status,
            "xlen": profile.xlen,
            "address_bits": profile.address_bits,
            "translation": profile.translation,
            "inherits": profile.inherits,
            "hardware_target": profile.hardware_target,
            "required_rules": set(profile.required_rules),
        }
        actual = {
            "status": entry.get("status"),
            "xlen": int(entry.get("xlen", 0)),
            "address_bits": int(entry.get("address_bits", 0)),
            "translation": entry.get("translation"),
            "inherits": entry.get("inherits"),
            "hardware_target": entry.get("hardware_target"),
            "required_rules": set(entry.get("required_rules", [])),
        }
        if actual != expected:
            fail(f"architecture entry differs for {name}\nJSON={actual}\nPython={expected}")

    json_system = manifest.get("system_profiles", {})
    if set(json_system) != set(SYSTEM_PROFILES):
        fail("system-profile names differ from Python")
    for name, profile in SYSTEM_PROFILES.items():
        entry = json_system[name]
        expected = {
            "architecture": profile.architecture,
            "status": profile.status,
            "mmu": profile.mmu,
            "userspace_abi": profile.userspace_abi,
            "virtual_address_bits": profile.virtual_address_bits,
        }
        actual = {key: entry.get(key) for key in expected}
        if actual != expected:
            fail(f"system profile differs for {name}\nJSON={actual}\nPython={expected}")

    print(
        f"family manifest synchronized: {len(ARCHITECTURES)} architectures, "
        f"{len(SYSTEM_PROFILES)} system profiles"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
