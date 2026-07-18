# Event contracts

Catálogo alinhado à máquina de estados de
[domain-model.md](../../docs/architecture/domain-model.md) e à ADR 0005.

```text
interaction.discovered
interaction.queued
interaction.claimed
interaction.confirmation_requested
interaction.confirmed
interaction.confirmation_timeout
interaction.cancelled
interaction.expired
transaction.denied
transaction.credit_reserved
transaction.completed
attraction.actuation_failed
transaction.reconciliation_required
transaction.actuation_override
gateway.status_changed
```

`transaction.completed` é o único evento automático que informa débito:
contém `ledger_entry_id` e `actuation_command_id`. Reserva não é ledger.
Eventos de resolução/override sempre carregam `operator_id` individual.

Todo evento possui `event_id`, `event_type`, `version`, `occurred_at`
(horário do servidor), `correlation_id` e `payload` validado — schema
executável em [events.schema.json](events.schema.json) (JSON Schema
2020-12), testado contra instâncias em [`examples/`](examples/). Eventos de negócio
(`interaction.*`, `transaction.*`, `attraction.*`) e telemetria técnica
(`gateway.*`) permanecem em namespaces separados (AGENTS.md).
