# Modelo de domínio

Modelo vigente após a correção da [ADR 0005](../decisions/0005-protocol-correction-and-transaction-safety.md).

## Entidades

```text
interaction_request
  interaction_id             PK, atribuído pelo servidor
  band_id                     FK, resolvido apenas no servidor
  session_nonce               8 bytes, único por band_id
  display_code
  protocol_version
  first_authenticated_at
  expires_at                  first_authenticated_at + request_ttl_seconds
  state

interaction_sighting
  sighting_id                 PK
  interaction_id              FK -> interaction_request
  gateway_id
  rssi
  received_at

interaction_claim
  claim_id                    PK
  interaction_id              FK -> interaction_request
  operator_gateway_id
  attraction_id
  claimed_at
  lease_expires_at
  attempt_count
  status                      active | released | expired

transaction_intent
  transaction_id              PK
  interaction_id              FK -> interaction_request, UNIQUE
  claim_id                     FK -> interaction_claim
  attraction_id
  operator_gateway_id
  radio_gateway_id
  amount
  challenge_nonce
  status

credit_reservation
  reservation_id              PK
  transaction_id              FK -> transaction_intent, UNIQUE
  band_id
  amount
  status                      active | consumed | released
  reserved_at
  resolved_at

actuation_command
  actuation_command_id         PK
  transaction_id              FK -> transaction_intent
  operator_gateway_id
  attraction_id
  attempt_number
  status                      pending | succeeded | not_executed | ambiguous
  created_at
  acknowledged_at

ledger_entry
  ledger_entry_id              PK
  transaction_id              FK -> transaction_intent, UNIQUE
  amount
  balance_after
  committed_at

operational_resolution
  resolution_id                PK
  transaction_id              FK -> transaction_intent
  operator_id                  identidade humana obrigatória
  operator_gateway_id
  action                      retry_actuation | release_reservation | manual_confirmation
  reason
  resolved_at
```

`interaction_claim` e `transaction_intent` nascem atomicamente. Uma
`credit_reservation` reduz o saldo disponível, mas não altera o ledger. O
`ledger_entry` nasce somente após ack positivo do acionamento e na mesma
transação que consome a reserva.

## Máquina de estados do servidor

```text
(none) --advertising autenticado e nonce novo--> discovered
discovered --código sem colisão--> queued
discovered --código colidente--> queued_ambiguous
queued_ambiguous --colisão deixa de existir ou novo código--> queued
discovered/queued/queued_ambiguous --expires_at--> expired

queued --claim CAS--> claimed
claimed --desafio GATT enviado--> awaiting_band_confirmation
claimed --lease expira, tentativa < 3--> queued
claimed --3 tentativas esgotadas--> expired

awaiting_band_confirmation --Decision válido--> confirmed_pending_validation
awaiting_band_confirmation --10s sem clique--> confirmation_timeout
awaiting_band_confirmation --Cancel vence a corrida--> cancelled

confirmed_pending_validation --saldo/regra inválidos--> denied
confirmed_pending_validation --reserva atômica criada--> credit_reserved
credit_reserved --comando persistido e enviado--> actuation_pending
actuation_pending --ack positivo do mesmo command_id; reserva vira débito--> completed
actuation_pending --ack not_executed--> actuation_failed
actuation_pending --timeout/ack ambíguo--> reconciliation_required
actuation_failed --retry auditado--> actuation_pending
actuation_failed --reserva liberada por operador identificado--> cancelled
reconciliation_required --entrega comprovada por operador identificado--> completed
reconciliation_required --não entrega comprovada; reserva liberada--> cancelled
```

Não existe auto-retry de acionamento físico. Retry reutiliza o resultado se o
`actuation_command_id` já for conhecido; um novo ID só é criado por resolução
auditada depois de falha explicitamente negativa.

Cancelamento é aceito até `credit_reserved`, antes do despacho do comando. Em
`actuation_pending`, somente ack `not_executed` ou reconciliação identificada
pode liberar a reserva. Depois do ledger, correções usam ajuste financeiro
auditado e nunca reabrem a transação original.

## Máquina de estados da pulseira

```text
idle --pressão longa--> advertising_request
advertising_request --desafio válido--> awaiting_confirmation
awaiting_confirmation --clique curto--> confirming
awaiting_confirmation --10s sem clique--> timeout
awaiting_confirmation/confirming --Cancel válido--> cancelled
confirming --Result denied--> denied
confirming --Result completed--> completed
confirming --30s sem resultado terminal--> attention_required
attention_required --Result/Cancel autenticado--> completed | denied | cancelled
```

Em `attention_required`, a pulseira mostra “PROCURE OPERADOR”, preserva o
`transaction_id` e continua anunciando a mesma solicitação. O servidor
deduplica por `(band_id, session_nonce)`, portanto a reconexão não cria outra
interação nem renova a expiração original.

## Mapeamento servidor ↔ pulseira

| Servidor | Pulseira | Observação |
|---|---|---|
| `discovered`, `queued`, `queued_ambiguous`, `claimed` | `advertising_request` | colisão é visível no TFT e não pode ser reivindicada |
| `awaiting_band_confirmation` | `awaiting_confirmation` | janela de clique de 10s |
| `confirmed_pending_validation`, `credit_reserved`, `actuation_pending` | `confirming` | progresso visual por até 30s |
| `denied` | `denied` | nenhum débito |
| `completed` | `completed` | acionamento confirmado e débito commitado uma vez |
| `cancelled` | `cancelled` | Cancel GATT quando houver conexão |
| `actuation_failed`, `reconciliation_required` | `attention_required` | exige operador; nenhum débito sem prova de entrega |

## Regras de expiração e replay

- `request_ttl_seconds` é contado a partir do primeiro sighting autenticado.
- Repetir o mesmo `session_nonce` não estende a expiração.
- `(band_id, session_nonce)` é único e durável no PostgreSQL.
- `transaction_counter` é usado na Decision GATT e deve crescer estritamente
  por pulseira; o valor é persistido antes da emissão da resposta.
