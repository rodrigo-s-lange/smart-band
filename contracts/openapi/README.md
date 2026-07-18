# OpenAPI e canais em tempo real

Especificação executável em [openapi.yaml](openapi.yaml) (OpenAPI 3.1,
validado com `openapi-spec-validator`). Cobre:

- health
- ingestão de sightings autenticados e resolução de identidade
- fila global (snapshot HTTP + stream SSE)
- claim e cancelamento de solicitações
- transações: status, resultado de acionamento, override manual, estados
  espelhando `docs/architecture/domain-model.md`
- ledger: consulta e ajuste manual (estorno)
- pulseiras, créditos, atrações, gateways, operadores — CRUD representativo;
  o conjunto completo é preenchido na Etapa 5 (backend local), seguindo o
  mesmo padrão de auth/versionamento/erro já fixado no arquivo

## Autenticação

- Gateways: API key estática por gateway (`Authorization: Bearer`), emitida
  no provisionamento. mTLS é endurecimento futuro (ADR 0003, Postergado).
- `operator-web`: sessão por cookie após login humano, reutilizada em modo
  kiosk.

## Versionamento

Prefixo de URL (`/v1/...`), fixado no `servers.url` da especificação —
simples de embutir em clientes HTTP de gateways com stack limitada (ESP32).

## Tempo real

Atualizações da fila usam Server-Sent Events (SSE) — decidido em
[ADR 0004](../../docs/decisions/0004-advertising-payload-and-transport.md).
Mutações (claim, cancelamento) viajam por HTTP REST; o canal SSE é somente
servidor → cliente.
