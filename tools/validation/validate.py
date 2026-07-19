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

    operation_statuses: dict[str, str | None] = {}
    for path_item in spec["paths"].values():
        for method, operation in path_item.items():
            if method not in {"get", "post", "put", "patch", "delete"}:
                continue
            operation_statuses[operation["operationId"]] = operation.get(
                "x-smartband-status"
            )
    expected_blocked = {"topUpCredits", "createAttraction", "provisionGateway"}
    actual_blocked = {
        operation_id
        for operation_id, status in operation_statuses.items()
        if status == "client-decision-blocked"
    }
    if actual_blocked != expected_blocked:
        raise AssertionError(
            "client-decision OpenAPI gates diverged: "
            f"expected {sorted(expected_blocked)}, got {sorted(actual_blocked)}"
        )


def cmac(key: bytes, message: bytes) -> bytes:
    calculator = CMAC(algorithms.AES(key))
    calculator.update(message)
    return calculator.finalize()


def decode_hex(value: str, label: str) -> bytes:
    try:
        return bytes.fromhex(value)
    except ValueError as exc:
        raise AssertionError(f"invalid hex in {label}") from exc


def encode_display_code(value: int) -> str:
    if not 0 <= value < 1 << 30:
        raise AssertionError("display code uses reserved upper bits")
    alphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
    symbols = [alphabet[(value >> (5 * (5 - index))) & 0x1F] for index in range(6)]
    return "".join(symbols[:3]) + "-" + "".join(symbols[3:])


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

    advertising = next(
        vector for vector in data["vectors"] if vector["name"] == "advertising"
    )
    advertising_wire = decode_hex(advertising["wire_payload_hex"], "advertising.wire")
    display_code_raw = int.from_bytes(advertising_wire[17:21], byteorder="little")
    if display_code_raw != advertising["display_code_raw_uint32"]:
        raise AssertionError("advertising display-code integer mismatch")
    if encode_display_code(display_code_raw) != advertising["display_code_text"]:
        raise AssertionError("advertising display-code symbol order mismatch")

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


def validate_documentation_handoff() -> None:
    required_paths = [
        ROOT / "CURRENT_STATE.md",
        ROOT / "docs/product/client-decisions-pending.md",
        ROOT / "docs/decisions/0011-client-decision-gate-and-safe-prework.md",
        ROOT / "docs/decisions/0012-radio-retry-and-opaque-transport.md",
        ROOT / "contracts/gateway/radio-dispatch.md",
    ]
    missing = [
        str(path.relative_to(ROOT)) for path in required_paths if not path.exists()
    ]
    if missing:
        raise AssertionError(f"missing handoff documents: {missing}")

    current = required_paths[0].read_text(encoding="utf-8")
    client_gate = required_paths[1].read_text(encoding="utf-8")
    agents = (ROOT / "AGENTS.md").read_text(encoding="utf-8")
    roadmap = (ROOT / "docs/roadmap.md").read_text(encoding="utf-8")
    stage_gate = (ROOT / "docs/stage-gates/05-backend-foundation.md").read_text(
        encoding="utf-8"
    )
    readme = (ROOT / "README.md").read_text(encoding="utf-8")

    migration_count = len(
        list((ROOT / "apps/edge-api/internal/postgres/migrations").glob("*.sql"))
    )
    count_match = re.search(r"Migrations vigentes: \*\*(\d+)\*\*", current)
    if not count_match or int(count_match.group(1)) != migration_count:
        documented = count_match.group(1) if count_match else "missing"
        raise AssertionError(
            f"CURRENT_STATE migration count {documented} != {migration_count}"
        )
    if f"as {migration_count} migrations" not in stage_gate:
        raise AssertionError("Stage 5 gate does not expose the current migration count")

    mandatory = [
        "CURRENT_STATE.md",
        "docs/product/client-decisions-pending.md",
        "docs/decisions/0011-client-decision-gate-and-safe-prework.md",
        "docs/decisions/0012-radio-retry-and-opaque-transport.md",
        "contracts/gateway/radio-dispatch.md",
    ]
    for path in mandatory:
        if path not in agents:
            raise AssertionError(f"AGENTS mandatory reading missing {path}")

    required_phrases = {
        "CURRENT_STATE.md": [
            "Quinta fatia da Etapa 5 — motor de retry de rádio e transporte simulado",
            "Não objetivos desta fatia",
            "Critérios de aceite",
            "client-decisions-pending.md",
            "radio-dispatch.md",
            "radio_attempts_exhausted",
        ],
        "client-decisions-pending.md": [
            "aguardando validação do cliente",
            "client-decision-blocked",
            "Trabalho permitido antes das respostas",
        ],
    }
    for label, phrases in required_phrases.items():
        source = current if label == "CURRENT_STATE.md" else client_gate
        absent = [phrase for phrase in phrases if phrase not in source]
        if absent:
            raise AssertionError(f"{label} missing handoff markers: {absent}")

    vault_pattern = re.compile(r"Vault commit validado: `([0-9a-f]{40})`")
    current_vault = vault_pattern.search(current)
    gate_vault = vault_pattern.search(client_gate)
    if not current_vault or not gate_vault:
        raise AssertionError("validated vault commit missing from handoff documents")
    if current_vault.group(1) != gate_vault.group(1):
        raise AssertionError("handoff documents reference different vault commits")

    retry_contract = required_paths[4].read_text(encoding="utf-8")
    retry_markers = [
        "confirmou tecnicamente a escrita completa",
        "ainda não usados pela transação",
        "radio_attempts_exhausted",
        "FOR UPDATE SKIP LOCKED",
        "transaction_intent` como `cancelled",
        "waiting_for_radio",
        "no_radio_gateway",
        "Nunca selecionar rádio por sighting",
    ]
    absent_retry = [marker for marker in retry_markers if marker not in retry_contract]
    if absent_retry:
        raise AssertionError(f"radio dispatch contract incomplete: {absent_retry}")

    active_documents = {
        "README.md": readme,
        "docs/roadmap.md": roadmap,
        "docs/stage-gates/05-backend-foundation.md": stage_gate,
    }
    stale_patterns = [
        r"\b(?:oito|nove|8|9) migrations\b",
        r"A próxima fatia da Etapa 5 despacha o Challenge",
        r"despacho GATT, confirmação e reserva são as próximas fatias",
    ]
    for label, source in active_documents.items():
        for pattern in stale_patterns:
            if re.search(pattern, source, flags=re.IGNORECASE):
                raise AssertionError(f"stale active documentation in {label}: {pattern}")

    decisions_index = (ROOT / "docs/decisions/README.md").read_text(encoding="utf-8")
    for path in sorted((ROOT / "docs/decisions").glob("[0-9][0-9][0-9][0-9]-*.md")):
        if f"({path.name})" not in decisions_index:
            raise AssertionError(f"ADR index missing {path.name}")


def main() -> int:
    checks = [
        ("event schema and examples", validate_events),
        ("OpenAPI", validate_openapi_contract),
        ("AES-CMAC vectors", validate_cmac_vectors),
        ("Markdown links", validate_markdown_links),
        ("documentation handoff consistency", validate_documentation_handoff),
    ]
    for label, check in checks:
        check()
        print(f"ok: {label}")
    print("Executable contract and handoff validation passed")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"validation failed: {exc}", file=sys.stderr)
        raise
