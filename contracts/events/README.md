# Event contracts

Catálogo corrigido para bater exatamente com a máquina de estados de
[domain-model.md](../../docs/architecture/domain-model.md): `interaction.rejected`
foi removido (não existe mais gesto de rejeição, ADR 0003), e
`interaction.confirmation_timeout`, `interaction.cancelled` e
`transaction.actuation_override` foram adicionados, porque correspondiam a
transições reais sem evento associado.

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
transaction.authorized
transaction.completed
attraction.actuation_failed
transaction.actuation_override
gateway.status_changed
```

Todo evento possui `event_id`, `event_type`, `version`, `occurred_at`
(horário do servidor), `correlation_id` e `payload` validado — schema
executável em [events.schema.json](events.schema.json) (JSON Schema
2020-12), testado contra instâncias válidas e inválidas. Eventos de negócio
(`interaction.*`, `transaction.*`, `attraction.*`) e telemetria técnica
(`gateway.*`) permanecem em namespaces separados (AGENTS.md).
