# Gate parcial da Etapa 5 — Backend local

Status: concluído — 2026-07-18

## Entregue nesta fatia

- binário Go com configuração somente por ambiente
- `pgxpool`, queries `sqlc` e mapeamento UUID ↔ IDs compactos
- health, readiness e contexto single-tenant/single-site
- snapshots autenticados de fila, atrações, gateways e pulseiras
- autenticação por hash de bearer token ou cookie de sessão
- logs estruturados, request ID e graceful shutdown
- imagem multi-stage com runtime distroless sem root
- testes unitários e integração contra PostgreSQL 18.4
- runbook de desenvolvimento e diagnóstico

## Endpoints executáveis

```text
GET /v1/health       público
GET /v1/ready        público
GET /v1/appliance    autenticado
GET /v1/queue        autenticado
GET /v1/attractions  autenticado
GET /v1/gateways     autenticado
GET /v1/bands        autenticado
```

## Validação

```bash
cd apps/edge-api
go test -race ./...
go vet ./...
go build ./cmd/edge-api
```

O workflow `Backend` também prepara as oito migrations em PostgreSQL real,
regenera o `sqlc`, compara o resultado versionado e constrói a imagem.

Evidência: workflow verde na PR 3 em
[GitHub Actions](https://github.com/rodrigo-s-lange/smart-band/actions/runs/29647127575),
além dos workflows `Contracts` e `Database`.

## Ainda necessário para concluir a Etapa 5

- validação da Decision GATT
- reserva, despacho, cancelamento, ack e reconciliação pela camada de aplicação
- provisioning seguro e login/PIN operacional

## Segunda fatia entregue

- parser do advertising v1 de 22 bytes e AES-128-CMAC validado contra RFC 4493
  e os vetores versionados do projeto
- resolução por busca entre pulseiras atribuídas à sessão ativa
- envelope AES-256-GCM para `band_key`, com KEK externa ao PostgreSQL
- `POST /v1/sightings` vinculado à identidade autenticada do gateway
- transação PostgreSQL para criação, deduplicação, colisão e outbox
- replay como novo sighting sem renovar o TTL original
- sequência monotônica de outbox e `GET /v1/queue/stream` com
  `Last-Event-ID`, heartbeat e expiração de descoberta

Detalhes e consequências: [ADR 0008](../decisions/0008-authenticated-sightings-and-sse.md).

## Terceira fatia entregue

- sessão do operador vinculada ao gateway físico e ao site
- `POST /v1/interactions/{interaction_id}/claim` conforme OpenAPI 1.4
- claim CAS concorrente com exatamente um vencedor
- escolha do rádio por sightings do servidor nos últimos 10 segundos, maior
  RSSI, maior recência e menor ID como desempate determinístico
- lease inicial de 10 segundos e `transaction_intent` em `claimed`
- claim, transaction intent e `interaction.claimed` atômicos no PostgreSQL
- `challenge_nonce` alinhado ao contrato BLE de 8 bytes
- upgrade seguro que invalida sessões sem vínculo e cancela desafios legados
  incompatíveis
- testes de concorrência, ausência de rádio e separação entre gateway operador
  e gateway de rádio

Detalhes e consequências: [ADR 0009](../decisions/0009-atomic-claim-and-radio-selection.md).
