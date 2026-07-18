# Gate da Etapa 4 — Modelo PostgreSQL

Status: candidato validado localmente — 2026-07-18

## Escopo entregue

- topologia single-tenant/single-site da ADR 0006
- eventos históricos com no máximo um evento ativo por site
- participantes, sessões, carteiras, pulseiras e assignments
- operadores, gateways, atrações e vínculo gateway–atração
- solicitações, sightings, claims e transaction intents
- reservas, comandos idempotentes, resoluções operacionais e ledger append-only
- outbox transacional e auditoria
- cinco migrations SQL com `goose Up` e `goose Down`

## Invariantes materializados

| Invariante | Proteção PostgreSQL |
|---|---|
| uma configuração por appliance | PK singleton com `CHECK (singleton_id = 1)` |
| um evento ativo por site | índice único parcial |
| um nonce por pulseira para sempre | `UNIQUE (band_id, session_nonce)` |
| uma interação ativa por pulseira | índice único parcial |
| um claim ativo por interação | índice único parcial |
| uma reserva por transação | `UNIQUE (transaction_id)` + trigger de coerência |
| um comando por tentativa | `UNIQUE (transaction_id, attempt_number)` |
| no máximo um débito por transação | índice único parcial de ledger |
| ledger imutável | trigger que rejeita `UPDATE` e `DELETE` |
| débito somente após entrega | função de ack exige comando e reserva válidos |
| sem double-spend concorrente | reserva serializada por lock da carteira |

## Validação executável

Entrada única:

```bash
python tools/database/validate.py --docker-container smartband-stage4-db
```

Executado no laboratório contra `postgres:18.4`:

```text
database validation passed: 5 migrations; invariants, concurrency, ambiguous
ack, cancel/dispatch race and rollback, including database restart
```

O teste disputa duas reservas de 80 sobre saldo 100 em conexões distintas. Uma
é aceita, uma é rejeitada e o saldo contábil permanece inalterado até o ack.
Também disputa cancelamento contra despacho: ou a reserva é liberada sem
comando, ou o comando permanece pendente com a reserva ativa. Ack ambíguo não
debita. O cenário de restart persiste reserva e comando, reinicia o PostgreSQL
e comprova que o ack posterior gera exatamente um débito.

O workflow `Database` repete migrations, invariantes, concorrência e rollback
em cada PR. O restart completo permanece uma prova adicional do laboratório,
porque o runner não controla o ciclo de vida do service container.

## Critério final

O gate passa quando o workflow `Database` estiver verde na PR desta etapa. A
Etapa 5 pode então consumir as funções transacionais e as tabelas por queries
SQL tipadas, sem deslocar regras de saldo para gateway ou pulseira.
