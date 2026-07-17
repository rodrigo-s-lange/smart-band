# Event contracts

Eventos iniciais:

```text
interaction.discovered
interaction.queued
interaction.claimed
interaction.confirmation_requested
interaction.confirmed
interaction.rejected
interaction.expired
transaction.authorized
transaction.completed
transaction.denied
attraction.actuation_failed
gateway.status_changed
```

Todo evento possui `event_id`, versão, horário do servidor, correlation ID e
payload validado. Eventos de negócio e telemetria técnica permanecem separados.
