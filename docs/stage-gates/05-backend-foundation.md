# Gate parcial da Etapa 5 — Fundação do backend

Status: candidato — 2026-07-18

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

O workflow `Backend` também prepara as seis migrations em PostgreSQL real,
regenera o `sqlc`, compara o resultado versionado e constrói a imagem.

## Ainda necessário para concluir a Etapa 5

- ingestão e autenticação do advertising de 22 bytes
- criação/deduplicação de sightings e publicação SSE
- claim CAS e escolha do gateway de rádio
- validação da Decision GATT
- reserva, despacho, cancelamento, ack e reconciliação pela camada de aplicação
- provisioning seguro e login/PIN operacional
