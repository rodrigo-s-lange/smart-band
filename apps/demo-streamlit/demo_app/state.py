from __future__ import annotations

import sqlite3
from contextlib import contextmanager
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path
from typing import Any, Iterator


ACTIVE_INTERACTION_STATES = {
    "requesting",
    "awaiting_confirmation",
    "confirmed",
    "reconciliation_required",
}


def utc_now() -> str:
    return datetime.now(UTC).isoformat(timespec="seconds")


@dataclass(frozen=True)
class DemoStore:
    path: Path

    def __post_init__(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.initialize()

    def connect(self) -> sqlite3.Connection:
        connection = sqlite3.connect(self.path, timeout=5)
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA foreign_keys = ON")
        connection.execute("PRAGMA journal_mode = WAL")
        connection.execute("PRAGMA busy_timeout = 5000")
        return connection

    @contextmanager
    def transaction(self) -> Iterator[sqlite3.Connection]:
        connection = self.connect()
        try:
            connection.execute("BEGIN IMMEDIATE")
            yield connection
            connection.commit()
        except Exception:
            connection.rollback()
            raise
        finally:
            connection.close()

    def initialize(self) -> None:
        with self.connect() as connection:
            connection.executescript(
                """
                CREATE TABLE IF NOT EXISTS participants (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    name TEXT NOT NULL,
                    birth_date TEXT NOT NULL,
                    contact TEXT NOT NULL,
                    guardian_name TEXT,
                    guardian_relationship TEXT,
                    guardian_contact TEXT,
                    operational_terms INTEGER NOT NULL CHECK (operational_terms IN (0, 1)),
                    marketing_consent INTEGER NOT NULL CHECK (marketing_consent IN (0, 1)),
                    created_at TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS attractions (
                    id TEXT PRIMARY KEY,
                    name TEXT NOT NULL UNIQUE,
                    cost_credits INTEGER NOT NULL CHECK (cost_credits > 0),
                    capability TEXT NOT NULL,
                    color TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS gateways (
                    id TEXT PRIMARY KEY,
                    friendly_name TEXT NOT NULL UNIQUE,
                    attraction_id TEXT REFERENCES attractions(id),
                    online INTEGER NOT NULL CHECK (online IN (0, 1)),
                    rssi INTEGER NOT NULL,
                    capability TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS bands (
                    id TEXT PRIMARY KEY,
                    code TEXT NOT NULL UNIQUE,
                    status TEXT NOT NULL,
                    balance INTEGER NOT NULL DEFAULT 0 CHECK (balance >= 0),
                    reserved INTEGER NOT NULL DEFAULT 0 CHECK (reserved >= 0),
                    battery INTEGER NOT NULL CHECK (battery BETWEEN 0 AND 100),
                    tamper_status TEXT NOT NULL,
                    participant_id INTEGER REFERENCES participants(id)
                );

                CREATE TABLE IF NOT EXISTS sales (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    participant_id INTEGER NOT NULL REFERENCES participants(id),
                    band_id TEXT NOT NULL REFERENCES bands(id),
                    credits INTEGER NOT NULL CHECK (credits > 0),
                    unit_price_cents INTEGER NOT NULL CHECK (unit_price_cents > 0),
                    payment_method TEXT NOT NULL,
                    status TEXT NOT NULL,
                    created_at TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS interactions (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    band_id TEXT NOT NULL REFERENCES bands(id),
                    code TEXT NOT NULL,
                    status TEXT NOT NULL,
                    attraction_id TEXT REFERENCES attractions(id),
                    operator_gateway_id TEXT REFERENCES gateways(id),
                    radio_gateway_id TEXT REFERENCES gateways(id),
                    radio_attempt INTEGER NOT NULL DEFAULT 1,
                    outcome TEXT,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS ledger (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    band_id TEXT NOT NULL REFERENCES bands(id),
                    delta INTEGER NOT NULL,
                    kind TEXT NOT NULL,
                    reference TEXT NOT NULL UNIQUE,
                    created_at TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS alerts (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    kind TEXT NOT NULL,
                    severity TEXT NOT NULL,
                    status TEXT NOT NULL,
                    band_id TEXT REFERENCES bands(id),
                    gateway_id TEXT REFERENCES gateways(id),
                    message TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS timeline (
                    sequence INTEGER PRIMARY KEY AUTOINCREMENT,
                    event_type TEXT NOT NULL,
                    title TEXT NOT NULL,
                    detail TEXT NOT NULL,
                    created_at TEXT NOT NULL
                );
                """
            )
            count = connection.execute("SELECT COUNT(*) FROM bands").fetchone()[0]
        if count == 0:
            self.reset()

    def _event(
        self,
        connection: sqlite3.Connection,
        event_type: str,
        title: str,
        detail: str,
        now: str,
    ) -> None:
        connection.execute(
            "INSERT INTO timeline(event_type, title, detail, created_at) VALUES (?, ?, ?, ?)",
            (event_type, title, detail, now),
        )

    def reset(self, now: str | None = None) -> None:
        timestamp = now or utc_now()
        attractions = [
            ("A1", "Corrida", 1, "Comando VR", "#5B8CFF"),
            ("A2", "Boxe", 1, "LED WS2812", "#FF5D7A"),
            ("A3", "Explorador", 1, "Relé", "#25C2A0"),
            ("A4", "Tiro", 1, "Comando serial", "#FFB84D"),
        ]
        gateways = [
            ("G1", "Gateway Corrida", "A1", 1, -48, "Comando VR"),
            ("G2", "Gateway Boxe", "A2", 1, -54, "LED WS2812"),
            ("G3", "Gateway Explorador", "A3", 1, -58, "Relé"),
            ("G4", "Gateway Tiro", "A4", 1, -51, "Comando serial"),
            ("G5", "Gateway Norte", None, 1, -62, "Ponte BLE"),
            ("G6", "Gateway Sul", None, 1, -65, "Ponte BLE"),
            ("G7", "Gateway Caixa", None, 1, -43, "Ponte BLE"),
            ("G8", "Gateway Reserva", None, 1, -70, "Ponte BLE"),
        ]
        codes = [
            "XTZ-2AC", "1YX-123", "3B9-2FF", "M7K-3PX", "7QH-4AD", "P2V-8NS",
            "K9M-2TR", "4CJ-7WX", "H6P-1ZA", "N3R-5KU", "8VD-9BF", "T4S-6GY",
            "2KL-8QJ", "W5X-3MN", "C7A-4RP", "F1G-9TV", "R8N-2HC", "J3D-7KS",
            "6PY-5WB", "A9T-1XM", "V2C-8QF", "L4H-6NR", "5MK-3ZD", "Q7W-9AP",
            "B1R-4TX", "G8V-2CJ", "S3N-6KL", "D9P-5WH", "Y4A-7MG", "E2K-8RS",
            "U6T-1BV", "Z5C-3QN",
        ]
        bands = [
            (f"B{index:02d}", code, "available", 0, 0, 96 - index % 24, "secure", None)
            for index, code in enumerate(codes, start=1)
        ]
        with self.transaction() as connection:
            for table in (
                "alerts", "ledger", "interactions", "sales", "bands", "gateways",
                "attractions", "participants", "timeline",
            ):
                connection.execute(f"DELETE FROM {table}")
            connection.execute("DELETE FROM sqlite_sequence")
            connection.executemany(
                "INSERT INTO attractions(id, name, cost_credits, capability, color) VALUES (?, ?, ?, ?, ?)",
                attractions,
            )
            connection.executemany(
                "INSERT INTO gateways(id, friendly_name, attraction_id, online, rssi, capability) VALUES (?, ?, ?, ?, ?, ?)",
                gateways,
            )
            connection.executemany(
                """INSERT INTO bands(
                    id, code, status, balance, reserved, battery, tamper_status, participant_id
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
                bands,
            )
            self._event(
                connection,
                "demo.reset",
                "Demonstração restaurada",
                "Fixture VRPlay Demo pronta: 8 gateways e 32 pulseiras fictícias.",
                timestamp,
            )

    def register_participant(
        self,
        *,
        name: str,
        birth_date: str,
        contact: str,
        band_id: str,
        guardian_name: str = "",
        guardian_relationship: str = "",
        guardian_contact: str = "",
        marketing_consent: bool = False,
        now: str | None = None,
    ) -> int:
        timestamp = now or utc_now()
        if not name.strip() or not contact.strip():
            raise ValueError("Nome e contato são obrigatórios na fixture da demo.")
        with self.transaction() as connection:
            band = connection.execute(
                "SELECT code, status FROM bands WHERE id = ?", (band_id,)
            ).fetchone()
            if band is None or band["status"] != "available":
                raise ValueError("Pulseira indisponível para vínculo.")
            cursor = connection.execute(
                """INSERT INTO participants(
                    name, birth_date, contact, guardian_name, guardian_relationship,
                    guardian_contact, operational_terms, marketing_consent, created_at
                ) VALUES (?, ?, ?, ?, ?, ?, 1, ?, ?)""",
                (
                    name.strip(), birth_date, contact.strip(), guardian_name.strip() or None,
                    guardian_relationship.strip() or None, guardian_contact.strip() or None,
                    int(marketing_consent), timestamp,
                ),
            )
            participant_id = int(cursor.lastrowid)
            connection.execute(
                "UPDATE bands SET status = 'linked', participant_id = ? WHERE id = ?",
                (participant_id, band_id),
            )
            self._event(
                connection,
                "participant.registered",
                "Participante fictício vinculado",
                f"{name.strip()} recebeu a pulseira {band['code']}.",
                timestamp,
            )
            return participant_id

    def create_sale(
        self,
        *,
        band_id: str,
        credits: int,
        payment_method: str,
        unit_price_cents: int = 2000,
        now: str | None = None,
    ) -> int:
        timestamp = now or utc_now()
        if credits <= 0:
            raise ValueError("A quantidade de créditos precisa ser positiva.")
        with self.transaction() as connection:
            band = connection.execute(
                "SELECT code, participant_id FROM bands WHERE id = ?", (band_id,)
            ).fetchone()
            if band is None or band["participant_id"] is None:
                raise ValueError("Vincule a pulseira antes de criar a venda.")
            pending = connection.execute(
                "SELECT id FROM sales WHERE band_id = ? AND status = 'pending'", (band_id,)
            ).fetchone()
            if pending:
                raise ValueError("Já existe pagamento pendente para esta pulseira.")
            cursor = connection.execute(
                """INSERT INTO sales(
                    participant_id, band_id, credits, unit_price_cents,
                    payment_method, status, created_at
                ) VALUES (?, ?, ?, ?, ?, 'pending', ?)""",
                (
                    band["participant_id"], band_id, credits, unit_price_cents,
                    payment_method, timestamp,
                ),
            )
            sale_id = int(cursor.lastrowid)
            self._event(
                connection,
                "sale.pending",
                "Pagamento simulado pendente",
                f"{credits} crédito(s) via {payment_method}; aguardando confirmação manual.",
                timestamp,
            )
            return sale_id

    def confirm_sale(self, sale_id: int, now: str | None = None) -> bool:
        timestamp = now or utc_now()
        with self.transaction() as connection:
            sale = connection.execute(
                "SELECT * FROM sales WHERE id = ?", (sale_id,)
            ).fetchone()
            if sale is None:
                raise ValueError("Venda não encontrada.")
            if sale["status"] == "confirmed":
                return False
            if sale["status"] != "pending":
                raise ValueError("A venda não pode mais ser confirmada.")
            connection.execute("UPDATE sales SET status = 'confirmed' WHERE id = ?", (sale_id,))
            connection.execute(
                "UPDATE bands SET balance = balance + ? WHERE id = ?",
                (sale["credits"], sale["band_id"]),
            )
            connection.execute(
                "INSERT INTO ledger(band_id, delta, kind, reference, created_at) VALUES (?, ?, 'credit_load_demo', ?, ?)",
                (sale["band_id"], sale["credits"], f"sale:{sale_id}", timestamp),
            )
            self._event(
                connection,
                "sale.confirmed",
                "Créditos simulados carregados",
                f"Venda #{sale_id} confirmada manualmente: {sale['credits']} crédito(s).",
                timestamp,
            )
            return True

    def cancel_sale(self, sale_id: int, now: str | None = None) -> bool:
        timestamp = now or utc_now()
        with self.transaction() as connection:
            updated = connection.execute(
                "UPDATE sales SET status = 'cancelled' WHERE id = ? AND status = 'pending'",
                (sale_id,),
            ).rowcount
            if updated:
                self._event(
                    connection,
                    "sale.cancelled",
                    "Venda simulada cancelada",
                    f"Venda #{sale_id} cancelada sem carregar créditos.",
                    timestamp,
                )
            return bool(updated)

    def press_band(self, band_id: str, now: str | None = None) -> int:
        timestamp = now or utc_now()
        with self.transaction() as connection:
            band = connection.execute("SELECT * FROM bands WHERE id = ?", (band_id,)).fetchone()
            if band is None or band["participant_id"] is None:
                raise ValueError("A pulseira ainda não está vinculada.")
            if band["balance"] - band["reserved"] < 1:
                raise ValueError("A pulseira não possui crédito disponível.")
            placeholders = ",".join("?" for _ in ACTIVE_INTERACTION_STATES)
            active = connection.execute(
                f"SELECT id FROM interactions WHERE band_id = ? AND status IN ({placeholders})",
                (band_id, *sorted(ACTIVE_INTERACTION_STATES)),
            ).fetchone()
            if active:
                return int(active["id"])
            cursor = connection.execute(
                """INSERT INTO interactions(
                    band_id, code, status, radio_attempt, created_at, updated_at
                ) VALUES (?, ?, 'requesting', 1, ?, ?)""",
                (band_id, band["code"], timestamp, timestamp),
            )
            interaction_id = int(cursor.lastrowid)
            self._event(
                connection,
                "interaction.requested",
                "Pulseira solicitou acesso",
                f"Código {band['code']} entrou no topo da fila global.",
                timestamp,
            )
            return interaction_id

    def claim_interaction(
        self,
        interaction_id: int,
        attraction_id: str,
        operator_gateway_id: str,
        now: str | None = None,
    ) -> bool:
        timestamp = now or utc_now()
        with self.transaction() as connection:
            attraction = connection.execute(
                "SELECT name FROM attractions WHERE id = ?", (attraction_id,)
            ).fetchone()
            gateway = connection.execute(
                "SELECT friendly_name FROM gateways WHERE id = ? AND online = 1",
                (operator_gateway_id,),
            ).fetchone()
            if attraction is None or gateway is None:
                raise ValueError("Atração ou gateway indisponível.")
            radio = connection.execute(
                "SELECT id FROM gateways WHERE online = 1 ORDER BY rssi DESC, id ASC LIMIT 1"
            ).fetchone()
            updated = connection.execute(
                """UPDATE interactions
                   SET status = 'awaiting_confirmation', attraction_id = ?,
                       operator_gateway_id = ?, radio_gateway_id = ?, updated_at = ?
                   WHERE id = ? AND status = 'requesting'""",
                (attraction_id, operator_gateway_id, radio["id"], timestamp, interaction_id),
            ).rowcount
            if updated:
                self._event(
                    connection,
                    "interaction.claimed",
                    "Solicitação selecionada",
                    f"{gateway['friendly_name']} selecionou {attraction['name']}; aguardando a pessoa.",
                    timestamp,
                )
            return bool(updated)

    def decide_interaction(
        self, interaction_id: int, confirm: bool, now: str | None = None
    ) -> bool:
        timestamp = now or utc_now()
        with self.transaction() as connection:
            interaction = connection.execute(
                """SELECT i.*, a.name AS attraction_name, a.cost_credits
                   FROM interactions i JOIN attractions a ON a.id = i.attraction_id
                   WHERE i.id = ?""",
                (interaction_id,),
            ).fetchone()
            if interaction is None or interaction["status"] != "awaiting_confirmation":
                return False
            if not confirm:
                connection.execute(
                    "UPDATE interactions SET status = 'cancelled', outcome = 'band_cancelled', updated_at = ? WHERE id = ?",
                    (timestamp, interaction_id),
                )
                self._event(
                    connection,
                    "interaction.cancelled",
                    "Pessoa cancelou na pulseira",
                    "Nenhum crédito foi reservado ou debitado.",
                    timestamp,
                )
                return True
            band = connection.execute(
                "SELECT balance, reserved FROM bands WHERE id = ?", (interaction["band_id"],)
            ).fetchone()
            if band["balance"] - band["reserved"] < interaction["cost_credits"]:
                raise ValueError("Saldo insuficiente para confirmar.")
            connection.execute(
                "UPDATE bands SET reserved = reserved + ? WHERE id = ?",
                (interaction["cost_credits"], interaction["band_id"]),
            )
            connection.execute(
                "UPDATE interactions SET status = 'confirmed', updated_at = ? WHERE id = ?",
                (timestamp, interaction_id),
            )
            self._event(
                connection,
                "interaction.confirmed",
                "Pessoa confirmou na pulseira",
                f"{interaction['attraction_name']}: 1 crédito reservado, ainda não debitado.",
                timestamp,
            )
            return True

    def actuate(
        self, interaction_id: int, outcome: str, now: str | None = None
    ) -> bool:
        if outcome not in {"succeeded", "not_executed", "ambiguous"}:
            raise ValueError("Resultado de acionamento inválido.")
        timestamp = now or utc_now()
        with self.transaction() as connection:
            interaction = connection.execute(
                """SELECT i.*, a.name AS attraction_name, a.cost_credits
                   FROM interactions i JOIN attractions a ON a.id = i.attraction_id
                   WHERE i.id = ?""",
                (interaction_id,),
            ).fetchone()
            if interaction is None or interaction["status"] != "confirmed":
                return False
            if outcome == "succeeded":
                connection.execute(
                    "UPDATE bands SET balance = balance - ?, reserved = reserved - ? WHERE id = ?",
                    (
                        interaction["cost_credits"], interaction["cost_credits"],
                        interaction["band_id"],
                    ),
                )
                connection.execute(
                    "INSERT INTO ledger(band_id, delta, kind, reference, created_at) VALUES (?, ?, 'attraction_debit_demo', ?, ?)",
                    (
                        interaction["band_id"], -interaction["cost_credits"],
                        f"interaction:{interaction_id}", timestamp,
                    ),
                )
                status, title, detail = (
                    "completed",
                    "Atração liberada e débito concluído",
                    f"{interaction['attraction_name']} confirmou o acionamento; 1 crédito debitado.",
                )
            elif outcome == "not_executed":
                connection.execute(
                    "UPDATE bands SET reserved = reserved - ? WHERE id = ?",
                    (interaction["cost_credits"], interaction["band_id"]),
                )
                status, title, detail = (
                    "actuation_failed",
                    "Atração não executada",
                    "Reserva liberada e nenhum crédito debitado.",
                )
            else:
                status, title, detail = (
                    "reconciliation_required",
                    "Resultado de liberação incerto",
                    "Reserva mantida; exige reconciliação e não haverá segundo acionamento automático.",
                )
            connection.execute(
                "UPDATE interactions SET status = ?, outcome = ?, updated_at = ? WHERE id = ?",
                (status, outcome, timestamp, interaction_id),
            )
            self._event(connection, f"actuation.{outcome}", title, detail, timestamp)
            return True

    def simulate_radio_fallback(self, interaction_id: int, now: str | None = None) -> bool:
        timestamp = now or utc_now()
        with self.transaction() as connection:
            interaction = connection.execute(
                "SELECT * FROM interactions WHERE id = ?", (interaction_id,)
            ).fetchone()
            if interaction is None or interaction["status"] not in {
                "requesting", "awaiting_confirmation"
            }:
                return False
            radio = connection.execute(
                """SELECT id, friendly_name FROM gateways
                   WHERE online = 1 AND id != COALESCE(?, '')
                   ORDER BY rssi DESC, id ASC LIMIT 1""",
                (interaction["radio_gateway_id"],),
            ).fetchone()
            if radio is None:
                raise ValueError("Nenhum gateway alternativo está disponível.")
            connection.execute(
                "UPDATE interactions SET radio_gateway_id = ?, radio_attempt = radio_attempt + 1, updated_at = ? WHERE id = ?",
                (radio["id"], timestamp, interaction_id),
            )
            self._event(
                connection,
                "radio.fallback",
                "Fallback de rádio executado",
                f"A mesma transação seguiu pela tentativa seguinte em {radio['friendly_name']}.",
                timestamp,
            )
            return True

    def set_gateway_online(
        self, gateway_id: str, online: bool, now: str | None = None
    ) -> None:
        timestamp = now or utc_now()
        with self.transaction() as connection:
            gateway = connection.execute(
                "SELECT friendly_name FROM gateways WHERE id = ?", (gateway_id,)
            ).fetchone()
            if gateway is None:
                raise ValueError("Gateway não encontrado.")
            connection.execute(
                "UPDATE gateways SET online = ? WHERE id = ?", (int(online), gateway_id)
            )
            self._event(
                connection,
                "gateway.status_changed",
                "Gateway online" if online else "Gateway offline",
                gateway["friendly_name"],
                timestamp,
            )

    def set_tamper(self, band_id: str, removed: bool, now: str | None = None) -> None:
        timestamp = now or utc_now()
        with self.transaction() as connection:
            band = connection.execute("SELECT code FROM bands WHERE id = ?", (band_id,)).fetchone()
            if band is None:
                raise ValueError("Pulseira não encontrada.")
            status = "removal_detected" if removed else "secure"
            connection.execute(
                "UPDATE bands SET tamper_status = ? WHERE id = ?", (status, band_id)
            )
            if removed:
                open_alert = connection.execute(
                    "SELECT id FROM alerts WHERE band_id = ? AND kind = 'tamper' AND status != 'resolved'",
                    (band_id,),
                ).fetchone()
                if open_alert is None:
                    connection.execute(
                        """INSERT INTO alerts(
                            kind, severity, status, band_id, message, created_at, updated_at
                        ) VALUES ('tamper', 'critical', 'new', ?, ?, ?, ?)""",
                        (
                            band_id, f"Remoção simulada detectada em {band['code']}.",
                            timestamp, timestamp,
                        ),
                    )
                title, detail = (
                    "Pulseira removida — conceito simulado",
                    f"Alerta crítico criado para {band['code']}; não representa sensor físico.",
                )
            else:
                title, detail = (
                    "Pulseira recolocada",
                    f"{band['code']} voltou ao estado seguro; alertas ainda exigem resolução humana.",
                )
            self._event(connection, f"tamper.{status}", title, detail, timestamp)

    def update_alert(self, alert_id: int, status: str, now: str | None = None) -> bool:
        if status not in {"acknowledged", "resolved"}:
            raise ValueError("Estado de alerta inválido.")
        timestamp = now or utc_now()
        with self.transaction() as connection:
            updated = connection.execute(
                "UPDATE alerts SET status = ?, updated_at = ? WHERE id = ? AND status != 'resolved'",
                (status, timestamp, alert_id),
            ).rowcount
            if updated:
                self._event(
                    connection,
                    f"alert.{status}",
                    "Alerta reconhecido" if status == "acknowledged" else "Alerta resolvido",
                    f"Alerta #{alert_id} atualizado manualmente.",
                    timestamp,
                )
            return bool(updated)

    def snapshot(self) -> dict[str, Any]:
        with self.connect() as connection:
            bands = [dict(row) for row in connection.execute(
                """SELECT b.*, p.name AS participant_name FROM bands b
                   LEFT JOIN participants p ON p.id = b.participant_id ORDER BY b.id"""
            )]
            gateways = [dict(row) for row in connection.execute(
                """SELECT g.*, a.name AS attraction_name FROM gateways g
                   LEFT JOIN attractions a ON a.id = g.attraction_id ORDER BY g.id"""
            )]
            attractions = [dict(row) for row in connection.execute(
                "SELECT * FROM attractions ORDER BY id"
            )]
            interactions = [dict(row) for row in connection.execute(
                """SELECT i.*, a.name AS attraction_name, a.cost_credits,
                          og.friendly_name AS operator_gateway_name,
                          rg.friendly_name AS radio_gateway_name
                   FROM interactions i
                   LEFT JOIN attractions a ON a.id = i.attraction_id
                   LEFT JOIN gateways og ON og.id = i.operator_gateway_id
                   LEFT JOIN gateways rg ON rg.id = i.radio_gateway_id
                   ORDER BY i.id DESC"""
            )]
            sales = [dict(row) for row in connection.execute(
                "SELECT * FROM sales ORDER BY id DESC"
            )]
            alerts = [dict(row) for row in connection.execute(
                "SELECT * FROM alerts ORDER BY id DESC"
            )]
            timeline = [dict(row) for row in connection.execute(
                "SELECT * FROM timeline ORDER BY sequence DESC LIMIT 40"
            )]
            ledger = [dict(row) for row in connection.execute(
                "SELECT * FROM ledger ORDER BY id DESC"
            )]
        linked = [band for band in bands if band["participant_id"] is not None]
        active_band = linked[0] if linked else bands[0]
        active_interaction = next(
            (
                interaction
                for interaction in interactions
                if interaction["status"] in ACTIVE_INTERACTION_STATES
            ),
            None,
        )
        return {
            "bands": bands,
            "gateways": gateways,
            "attractions": attractions,
            "interactions": interactions,
            "sales": sales,
            "alerts": alerts,
            "timeline": timeline,
            "ledger": ledger,
            "active_band": active_band,
            "active_interaction": active_interaction,
        }

    def metrics(self) -> dict[str, int]:
        snapshot = self.snapshot()
        confirmed_sales = [sale for sale in snapshot["sales"] if sale["status"] == "confirmed"]
        return {
            "participants": len([band for band in snapshot["bands"] if band["participant_id"]]),
            "bands_in_use": len([band for band in snapshot["bands"] if band["participant_id"]]),
            "gateways_online": len([gateway for gateway in snapshot["gateways"] if gateway["online"]]),
            "credits_loaded": sum(sale["credits"] for sale in confirmed_sales),
            "credits_consumed": -sum(
                item["delta"] for item in snapshot["ledger"] if item["delta"] < 0
            ),
            "revenue_cents": sum(
                sale["credits"] * sale["unit_price_cents"] for sale in confirmed_sales
            ),
            "open_alerts": len([alert for alert in snapshot["alerts"] if alert["status"] != "resolved"]),
        }

