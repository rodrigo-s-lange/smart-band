# ADR 0007 — Fundação do edge-api local

Status: accepted — 2026-07-18

## Contexto

A Etapa 4 materializou UUIDs persistentes, enquanto o contrato de rádio e a API
operacional usam identificadores compactos. A primeira fatia do backend também
precisa iniciar, observar e encerrar de forma previsível, sem depender da
internet ou do host do laboratório.

## Decisão

- `apps/edge-api` é um serviço Go 1.26 em monólito modular
- HTTP usa `net/http`; não há framework web obrigatório
- PostgreSQL usa `pgx/v5` e pool nativo
- queries são SQL explícito com código tipado pelo `sqlc` 1.31.1
- UUIDs permanecem internos; IDs compactos recebem colunas únicas de fronteira
- tokens de gateway e sessão possuem pelo menos 256 bits aleatórios em produção
  e somente SHA-256 é persistido
- `/v1/health` mede disponibilidade do processo e banco
- `/v1/ready` também exige a configuração singleton da appliance
- logs HTTP são estruturados e incluem request ID, latência e status, nunca token
- encerramento por SIGINT/SIGTERM é gracioso e limitado por timeout

A migration 00006 faz backfill determinístico dos IDs compactos para bancos de
desenvolvimento existentes. Credenciais antigas recebem hash inválido e precisam
ser reprovisionadas; nenhuma chave utilizável é inventada pela migration.

## Consequências

- o backend pode ser compilado e executado em qualquer host Linux compatível
- o contrato OpenAPI 1.2 passa a expor readiness e contexto da appliance
- fila e inventário usam uma única projeção PostgreSQL tipada
- geração do `sqlc` é verificada na CI para impedir código gerado divergente
- esta fatia não implementa ingestão criptográfica, claim, confirmação ou
  mutações financeiras HTTP; esses fluxos continuam como próximas fatias da
  Etapa 5
