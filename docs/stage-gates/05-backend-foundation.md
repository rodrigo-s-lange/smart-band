# Gate da fundação da Etapa 5 — Backend local

Status: fundação concluída; Etapa 5 em execução — 2026-07-18

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

O workflow `Backend` também prepara as 10 migrations em PostgreSQL real,
regenera o `sqlc`, compara o resultado versionado e constrói a imagem.

Evidência: workflow verde na PR 3 em
[GitHub Actions](https://github.com/rodrigo-s-lange/smart-band/actions/runs/29647127575),
além dos workflows `Contracts` e `Database`.

## Ainda necessário para concluir a Etapa 5

- validação da Decision GATT
- reserva, despacho, cancelamento, ack e reconciliação pela camada de aplicação
- provisioning seguro de gateways e administração local

Partes dependentes de cadastro, pagamentos, preço, duração, acionamento e perfis
administrativos aguardam o gate da ADR 0011 e não são escopo implícito deste
gate de fundação.

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

- gateway cadastrado como identidade operacional, sem login individual
- `POST /v1/interactions/{interaction_id}/claim` conforme OpenAPI 1.5
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

## Quarta fatia entregue

- gateway cadastrado confirmado como identidade operacional, sem operador humano;
- migration 00009 remove identidade e sessão humana do schema vigente;
- migration 00010 inclui `actuation_failed` no bloqueio de interação por pulseira;
- retry de rádio esclarecido como continuidade do mesmo claim e transação;
- evento ambíguo separado de falha comprovada;
- conversão Crockford documentada e validada por vetor executável;
- OpenAPI 1.6 marca operações dependentes do cliente como bloqueadas;
- Contracts, Database e Backend verdes na PR 7.

Evidência: merge `4019f7171bc8d8f91872831bba338c1d6a88b572`.

## Próxima fatia autorizada

Motor de retry de rádio e transporte simulado de payload opaco, conforme
[CURRENT_STATE.md](../../CURRENT_STATE.md) e a
[ADR 0012](../decisions/0012-radio-retry-and-opaque-transport.md). O Challenge/Decision final e os
contratos administrativos dependentes do cliente permanecem bloqueados pela
[ADR 0011](../decisions/0011-client-decision-gate-and-safe-prework.md).
