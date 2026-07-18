#!/usr/bin/env python3
"""Validação reproduzível dos contratos da Etapa 3."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

import yaml
from cryptography.hazmat.primitives.cmac import CMAC
from cryptography.hazmat.primitives.ciphers import algorithms
from jsonschema import Draft202012Validator, FormatChecker
from openapi_spec_validator import validate_spec


ROOT = Path(__file__).resolve().parents[2]


def load_json(path: Path) -> object:
    return json.loads(path.read_text(encoding="utf-8"))


def validate_events() -> None:
    schema_path = ROOT / "contracts/events/events.schema.json"
    schema = load_json(schema_path)
    Draft202012Validator.check_schema(schema)
    validator = Draft202012Validator(schema, format_checker=FormatChecker())

    examples = ROOT / "contracts/events/examples"
    valid_files = sorted((examples / "valid").glob("*.json"))
    invalid_files = sorted((examples / "invalid").glob("*.json"))
    if not valid_files or not invalid_files:
        raise AssertionError("event examples require valid and invalid cases")

    for path in valid_files:
        errors = list(validator.iter_errors(load_json(path)))
        if errors:
            raise AssertionError(f"valid event rejected: {path}: {errors[0].message}")

    for path in invalid_files:
        errors = list(validator.iter_errors(load_json(path)))
        if not errors:
            raise AssertionError(f"invalid event accepted: {path}")


def validate_openapi_contract() -> None:
    path = ROOT / "contracts/openapi/openapi.yaml"
    spec = yaml.safe_load(path.read_text(encoding="utf-8"))
    validate_spec(spec)

    states = set(
        spec["components"]["schemas"]["TransactionStatus"]["properties"]
        ["state"]["enum"]
    )
    required_states = {
        "credit_reserved",
        "actuation_pending",
        "actuation_failed",
        "reconciliation_required",
        "completed",
    }
    if not required_states <= states:
        raise AssertionError(f"OpenAPI missing transaction states: {required_states - states}")

    results = set(
        spec["components"]["schemas"]["ActuationResult"]["properties"]
        ["result"]["enum"]
    )
    expected_results = {"succeeded", "not_executed", "ambiguous"}
    if results != expected_results:
        raise AssertionError(f"unexpected actuation results: {results}")

    override_required = set(
        spec["components"]["schemas"]["ActuationOverrideRequest"]["required"]
    )
    if not {"action", "reason"} <= override_required:
        raise AssertionError("operational override must declare action and reason")


def cmac(key: bytes, message: bytes) -> bytes:
    calculator = CMAC(algorithms.AES(key))
    calculator.update(message)
    return calculator.finalize()


def decode_hex(value: str, label: str) -> bytes:
    try:
        return bytes.fromhex(value)
    except ValueError as exc:
        raise AssertionError(f"invalid hex in {label}") from exc


def validate_cmac_vectors() -> None:
    data = load_json(ROOT / "contracts/proximity/test-vectors.json")
    key = decode_hex(data["band_key_hex"], "band_key_hex")
    if len(key) != 16:
        raise AssertionError("AES-128 key must be 16 bytes")

    seen_domains: set[int] = set()
    for vector in data["vectors"]:
        name = vector["name"]
        message = decode_hex(vector["cmac_input_hex"], f"{name}.cmac_input_hex")
        wire = decode_hex(vector["wire_payload_hex"], f"{name}.wire_payload_hex")
        full = cmac(key, message)
        expected_full = decode_hex(vector["expected_full_cmac_hex"], name)
        expected_tag = decode_hex(vector["expected_tag_hex"], name)
        if full != expected_full or full[:8] != expected_tag:
            raise AssertionError(f"CMAC mismatch: {name}")
        if len(wire) != vector["wire_length_bytes"]:
            raise AssertionError(f"wire length mismatch: {name}")
        if message[0] != vector["domain_byte"]:
            raise AssertionError(f"domain mismatch: {name}")
        if message[0] in seen_domains:
            raise AssertionError(f"domain byte reused: {name}")
        seen_domains.add(message[0])
    if seen_domains != {1, 2, 3, 4, 5}:
        raise AssertionError(f"unexpected CMAC domains: {seen_domains}")

    tamper = data["tampering_cases"][0]
    original = decode_hex(tamper["original_cmac_input_hex"], "tamper.original")
    changed = decode_hex(tamper["tampered_cmac_input_hex"], "tamper.changed")
    original_tag = cmac(key, original)[:8]
    changed_tag = cmac(key, changed)[:8]
    if original_tag == changed_tag:
        raise AssertionError("tampering did not change Decision tag")
    if changed_tag.hex() != tamper["expected_tampered_tag_hex"]:
        raise AssertionError("tampered Decision vector mismatch")


MARKDOWN_LINK = re.compile(r"\[[^\]]+\]\(([^)]+)\)")


def validate_markdown_links() -> None:
    missing: list[str] = []
    for path in ROOT.rglob("*.md"):
        for target in MARKDOWN_LINK.findall(path.read_text(encoding="utf-8")):
            if "://" in target or target.startswith(("#", "mailto:")):
                continue
            relative = target.split("#", 1)[0]
            if relative and not (path.parent / relative).resolve().exists():
                missing.append(f"{path.relative_to(ROOT)} -> {target}")
    if missing:
        raise AssertionError("missing Markdown links:\n" + "\n".join(missing))


def main() -> int:
    checks = [
        ("event schema and examples", validate_events),
        ("OpenAPI", validate_openapi_contract),
        ("AES-CMAC vectors", validate_cmac_vectors),
        ("Markdown links", validate_markdown_links),
    ]
    for label, check in checks:
        check()
        print(f"ok: {label}")
    print("Stage 3 contract validation passed")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"validation failed: {exc}", file=sys.stderr)
        raise
