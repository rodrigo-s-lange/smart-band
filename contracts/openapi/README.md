# OpenAPI e canais em tempo real

Especificação executável em [openapi.yaml](openapi.yaml) (OpenAPI 3.1,
validado com `openapi-spec-validator`). Cobre:

- health
- ingestão de sightings autenticados e resolução de identidade
- fila global (snapshot HTTP + stream SSE)
- claim e cancelamento de solicitações
- transações: reserva, comando idempotente, resultado de acionamento,
  reconciliação identificada e estados
  espelhando `docs/architecture/domain-model.md`
- ledger: consulta e ajuste administrativo local com motivo obrigatório
- pulseiras, créditos, atrações e gateways — projeções e CRUD representativos;
  operações dependentes de decisão do cliente usam
  `x-smartband-status: client-decision-blocked` e não autorizam implementação
  definitiva antes da ADR correspondente

O resumo dos bloqueios está em
[client-decisions-pending.md](../../docs/product/client-decisions-pending.md).
Schemas representativos não definem política final de preço, duração,
capabilities, enrollment, pagamento ou perfil administrativo.

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
