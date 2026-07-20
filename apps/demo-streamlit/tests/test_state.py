from __future__ import annotations

import pytest

from demo_app.state import CROCKFORD, DemoStore, add_seconds, rotate_code


NOW = "2026-07-19T12:00:00+00:00"


def prepared_store(tmp_path) -> DemoStore:
    store = DemoStore(tmp_path / "demo.sqlite3")
    store.reset(NOW)
    return store


def prepare_balance(store: DemoStore, credits: int = 5) -> str:
    snapshot = store.snapshot(NOW)
    band = snapshot["bands"][0]
    store.register_participant(
        name="João Demo",
        birth_date="2000-01-01",
        contact="(00) 90000-0000",
        band_id=band["id"],
        now=NOW,
    )
    sale_id = store.create_sale(
        band_id=band["id"], credits=credits, payment_method="Pix", now=NOW
    )
    assert store.confirm_sale(sale_id, NOW)
    assert not store.confirm_sale(sale_id, NOW)
    return band["id"]


def test_reset_is_deterministic_and_shared(tmp_path) -> None:
    path = tmp_path / "demo.sqlite3"
    first = DemoStore(path)
    first.reset(NOW)
    second = DemoStore(path)
    third = DemoStore(path)
    assert len(first.snapshot(NOW)["bands"]) == 32
    assert len(second.snapshot(NOW)["gateways"]) == 8
    first.register_participant(
        name="João Demo",
        birth_date="2000-01-01",
        contact="demo@example.invalid",
        band_id="B01",
        now=NOW,
    )
    assert second.snapshot(NOW)["active_band"]["participant_name"] == "João Demo"
    assert third.snapshot(NOW)["active_band"]["participant_name"] == "João Demo"
    second.reset(NOW)
    assert first.snapshot(NOW)["bands"][0]["status"] == "available"
    assert third.snapshot(NOW)["interactions"] == []
    codes = {band["code"] for band in first.snapshot(NOW)["bands"]}
    rotated_codes = set()
    for band in first.snapshot(NOW)["bands"]:
        assert set(band["code"].replace("-", "")) <= set(CROCKFORD)
        rotated = rotate_code(band["code"])
        assert rotated != band["code"]
        rotated_codes.add(rotated)
    assert not (codes & rotated_codes)


def test_happy_path_is_repeatable_after_three_resets(tmp_path) -> None:
    store = DemoStore(tmp_path / "demo.sqlite3")
    for _ in range(3):
        store.reset(NOW)
        band_id = prepare_balance(store)
        interaction_id = store.press_band(band_id, NOW)
        assert store.claim_interaction(interaction_id, "A1", "G1", NOW)
        assert store.decide_interaction(interaction_id, True, NOW)
        assert store.actuate(interaction_id, "succeeded", NOW)
        snapshot = store.snapshot(NOW)
        band = next(item for item in snapshot["bands"] if item["id"] == band_id)
        assert band["balance"] == 4
        assert len([item for item in snapshot["ledger"] if item["delta"] < 0]) == 1


def test_happy_path_debits_exactly_once(tmp_path) -> None:
    store = prepared_store(tmp_path)
    band_id = prepare_balance(store)
    interaction_id = store.press_band(band_id, NOW)
    assert store.press_band(band_id, NOW) == interaction_id
    assert store.claim_interaction(interaction_id, "A1", "G1", NOW)
    assert store.decide_interaction(interaction_id, True, NOW)
    assert store.actuate(interaction_id, "succeeded", NOW)
    assert not store.actuate(interaction_id, "succeeded", NOW)
    snapshot = store.snapshot(NOW)
    band = next(item for item in snapshot["bands"] if item["id"] == band_id)
    debits = [item for item in snapshot["ledger"] if item["delta"] < 0]
    assert band["balance"] == 4
    assert band["reserved"] == 0
    assert len(debits) == 1


def test_not_executed_releases_reservation_without_debit(tmp_path) -> None:
    store = prepared_store(tmp_path)
    band_id = prepare_balance(store, credits=3)
    interaction_id = store.press_band(band_id, NOW)
    store.claim_interaction(interaction_id, "A2", "G2", NOW)
    store.decide_interaction(interaction_id, True, NOW)
    assert store.actuate(interaction_id, "not_executed", NOW)
    snapshot = store.snapshot(NOW)
    band = next(item for item in snapshot["bands"] if item["id"] == band_id)
    assert band["balance"] == 3
    assert band["reserved"] == 0
    assert not [item for item in snapshot["ledger"] if item["delta"] < 0]


def test_ambiguous_keeps_reservation_and_blocks_second_request(tmp_path) -> None:
    store = prepared_store(tmp_path)
    band_id = prepare_balance(store, credits=3)
    interaction_id = store.press_band(band_id, NOW)
    store.claim_interaction(interaction_id, "A3", "G3", NOW)
    store.decide_interaction(interaction_id, True, NOW)
    assert store.actuate(interaction_id, "ambiguous", NOW)
    snapshot = store.snapshot(NOW)
    band = next(item for item in snapshot["bands"] if item["id"] == band_id)
    assert band["balance"] == 3
    assert band["reserved"] == 1
    assert store.press_band(band_id, NOW) == interaction_id


def test_radio_fallback_preserves_interaction_and_tamper_is_audited(tmp_path) -> None:
    store = prepared_store(tmp_path)
    band_id = prepare_balance(store)
    interaction_id = store.press_band(band_id, NOW)
    store.claim_interaction(interaction_id, "A4", "G4", NOW)
    before = store.snapshot(NOW)["active_interaction"]
    assert store.simulate_radio_fallback(interaction_id, NOW)
    after = store.snapshot(NOW)["active_interaction"]
    assert after["id"] == before["id"]
    assert after["radio_attempt"] == before["radio_attempt"] + 1
    store.set_tamper(band_id, True, NOW)
    store.set_tamper(band_id, True, NOW)
    alerts = store.snapshot(NOW)["alerts"]
    assert len(alerts) == 1
    assert store.update_alert(alerts[0]["id"], "acknowledged", NOW)
    assert store.update_alert(alerts[0]["id"], "resolved", NOW)


def test_discovery_and_confirmation_expire_at_thirty_seconds(tmp_path) -> None:
    store = prepared_store(tmp_path)
    band_id = prepare_balance(store)
    first_code = store.snapshot(NOW)["active_band"]["code"]
    interaction_id = store.press_band(band_id, NOW)
    assert store.snapshot(add_seconds(NOW, 29))["active_interaction"]["id"] == interaction_id
    expired = store.snapshot(add_seconds(NOW, 30))
    assert expired["active_interaction"] is None
    assert expired["interactions"][0]["outcome"] == "discovery_timeout"
    assert expired["active_band"]["code"] != first_code

    second_id = store.press_band(band_id, add_seconds(NOW, 31))
    assert store.claim_interaction(second_id, "A1", "G1", add_seconds(NOW, 31))
    confirmation_expired = store.snapshot(add_seconds(NOW, 61))
    assert confirmation_expired["active_interaction"] is None
    assert confirmation_expired["interactions"][0]["outcome"] == "confirmation_timeout"


def test_session_counts_down_blocks_reentry_and_requires_operator_ack(tmp_path) -> None:
    store = prepared_store(tmp_path)
    band_id = prepare_balance(store)
    interaction_id = store.press_band(band_id, NOW)
    assert store.claim_interaction(interaction_id, "A1", "G1", NOW)
    assert store.decide_interaction(interaction_id, True, NOW)
    assert store.actuate(interaction_id, "succeeded", NOW)

    active = store.snapshot(NOW)
    assert active["active_session"]["session_remaining_seconds"] == 300
    with pytest.raises(ValueError, match="sessão em andamento"):
        store.press_band(band_id, add_seconds(NOW, 1))
    assert store.snapshot(add_seconds(NOW, 270))["active_session"][
        "session_remaining_seconds"
    ] == 30

    ended = store.snapshot(add_seconds(NOW, 300))
    assert ended["active_session"] is None
    assert ended["pending_gateway_end"]["id"] == interaction_id
    assert store.acknowledge_session_end(interaction_id, add_seconds(NOW, 301))
    assert store.snapshot(add_seconds(NOW, 301))["pending_gateway_end"] is None
    assert store.press_band(band_id, add_seconds(NOW, 302)) > interaction_id


def test_band_can_end_session_early_without_refund(tmp_path) -> None:
    store = prepared_store(tmp_path)
    band_id = prepare_balance(store)
    interaction_id = store.press_band(band_id, NOW)
    store.claim_interaction(interaction_id, "A1", "G1", NOW)
    store.decide_interaction(interaction_id, True, NOW)
    store.actuate(interaction_id, "succeeded", NOW)
    assert store.end_session(band_id, add_seconds(NOW, 60))
    snapshot = store.snapshot(add_seconds(NOW, 60))
    assert snapshot["active_session"] is None
    assert snapshot["pending_gateway_end"]["session_end_reason"] == "band"
    assert snapshot["active_band"]["balance"] == 4
