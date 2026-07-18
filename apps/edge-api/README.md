# Edge API

Aplicação principal da appliance local e autoridade transacional.

## Responsabilidades

- participantes, sessões e associação de pulseiras
- gateways, atrações e operadores
- ingestão autenticada de sightings
- fila global, claims e transaction intents
- desafio e validação da confirmação da pulseira
- reserva de crédito, comandos de acionamento, ledger, saldo, carga, débito,
  estorno e ajuste
- auditoria, health checks, backup e restore
- reconciliação e exceções vinculadas a `operator_id`

## Restrições

- não depende de internet para operar
- não confia em saldo informado por pulseira ou gateway
- não expõe banco diretamente à LAN
- não mistura telemetria técnica com ledger

## PostgreSQL

As migrations SQL ficam em `internal/postgres/migrations` e são compatíveis
com goose. A primeira fatia materializa o escopo single-tenant/single-site,
inventário, operação, interações, reservas, comandos, ledger append-only,
outbox e auditoria.

O schema oferece duas operações transacionais estreitas:

- `smartband_reserve_credit(transaction_id)` serializa reservas por carteira;
- `smartband_dispatch_actuation(transaction_id, command_id)` persiste o
  despacho antes do envio físico;
- `smartband_cancel_before_dispatch(transaction_id)` disputa o mesmo lock e
  nunca libera uma reserva depois que o comando venceu a corrida;
- `smartband_record_actuation_ack(command_id, result, timestamp)` converte a
  reserva em um único débito somente para ack `succeeded`.

Validação local e de CI: [tools/database/README.md](../../tools/database/README.md).

## Execução

```bash
export DATABASE_URL='postgresql://user:password@postgres:5432/smartband?sslmode=disable'
go run ./cmd/edge-api
```

Configuração adicional e valores padrão ficam em [.env.example](.env.example).
O serviço expõe health/readiness públicos e exige bearer token de gateway ou
cookie `sb_session` nos endpoints operacionais de leitura.

```bash
go test -race ./...
go vet ./...
go build ./cmd/edge-api
```

Arquitetura da fatia: [ADR 0007](../../docs/decisions/0007-edge-api-foundation.md).
