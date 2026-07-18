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
- `smartband_claim_interaction(...)` realiza o claim CAS, escolhe a ponte BLE
  recente e cria claim, transaction intent e outbox atomicamente.

Validação local e de CI: [tools/database/README.md](../../tools/database/README.md).

## Execução

```bash
export DATABASE_URL='postgresql://user:password@postgres:5432/smartband?sslmode=disable'
go run ./cmd/edge-api
```

Configuração adicional e valores padrão ficam em [.env.example](.env.example).
O serviço expõe health/readiness públicos e exige bearer token de gateway ou
cookie `sb_session` nos endpoints operacionais de leitura.

`POST /v1/interactions/{interaction_id}/claim` exige sessão de operador
vinculada ao `operator_gateway_id`. O retorno inclui a ponte BLE escolhida e o
fim do lease de 10 segundos. `no_radio_gateway` não cria estado parcial.

Sightings usam `POST /v1/sightings`. A credencial precisa pertencer ao mesmo
`gateway_id` do corpo; payloads não autenticados retornam `resolved=false` e não
entram na fila. O stream `GET /v1/queue/stream` publica envelopes do outbox com
ID monotônico e aceita `Last-Event-ID`.

`SMARTBAND_BAND_KEY_KEK_FILE` aponta para um arquivo de 32 bytes (bruto ou
Base64) montado fora do banco e do repositório. Em produção, restringir leitura
ao usuário do processo e incluir a KEK no procedimento separado de backup e
restore; não copiá-la para a imagem.

```bash
go test -race ./...
go vet ./...
go build ./cmd/edge-api
```

Arquitetura da fatia: [ADR 0007](../../docs/decisions/0007-edge-api-foundation.md),
[ADR 0008](../../docs/decisions/0008-authenticated-sightings-and-sse.md) e
[ADR 0009](../../docs/decisions/0009-atomic-claim-and-radio-selection.md).
