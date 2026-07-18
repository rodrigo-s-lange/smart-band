# Modelo de domínio

Formalização das entidades, relações e máquinas de estado descritas em
[interaction-queue.md](interaction-queue.md), [transaction-flow.md](transaction-flow.md),
[contracts/proximity/README.md](../../contracts/proximity/README.md) e
[ADR 0003](../decisions/0003-ble-protocol-parameters.md). Este documento não
introduz fronteira ou autoridade nova além do que já está decidido nos ADRs —
apenas organiza entidades, transições e invariantes em um único lugar
verificável.

## Entidades

```text
interaction_request
  interaction_id            PK, atribuído pelo servidor (ADR 0004)
  session_nonce              recebido da pulseira; usado na resolução de identidade (ADR 0003)
  display_code
  protocol_version
  created_at
  expires_at_local
  state

interaction_sighting
  sighting_id                PK
  interaction_id              FK -> interaction_request
  gateway_id
  rssi
  received_at

interaction_claim
  claim_id                    PK
  interaction_id              FK -> interaction_request (no máximo 1 claim ativo)
  operator_gateway_id
  attraction_id
  claimed_at
  lease_expires_at
  attempt_count                máx. 3 (ADR 0003)
  status                       active | released | expired

transaction_intent
  transaction_id               PK
  interaction_id                FK -> interaction_request
  claim_id                      FK -> interaction_claim
  attraction_id
  operator_gateway_id
  radio_gateway_id              nullable até escolha do rádio
  amount
  challenge_nonce               um por tentativa de rádio (ADR 0003)
  status

ledger_entry
  ledger_entry_id                PK
  transaction_id                  FK -> transaction_intent (1:1, criado só no débito)
  amount
  balance_after
  committed_at

actuation_override
  override_id                      PK
  transaction_id                    FK -> transaction_intent
  operator_gateway_id
  triggered_at
```

### Relação `interaction_claim` / `transaction_intent`

`interaction-queue.md` lista `transaction_intent` como entidade própria, sem
detalhar quando nasce. `transaction-flow.md` diz que o `transaction_id` é
criado no mesmo passo do claim atômico. Resolução:

- `interaction_claim` e `transaction_intent` nascem na mesma transação de
  banco do claim (compare-and-swap). `claim_id` e `transaction_id` estão
  vinculados 1:1 desde a criação.
- `ledger_entry` só é criado no momento do débito (transição `authorized`),
  nunca antes. Isso mantém "saldo e ledger mudam na mesma transação" sem
  exigir um `ledger_entry` para interações que nunca chegam a confirmar.
- `actuation_failed` ocorre **depois** do `ledger_entry` já existir. Por
  decisão da ADR 0003, essa falha nunca é revertida automaticamente: a
  resolução é um `actuation_override` (acionamento manual pelo operador,
  auditado por `operator_gateway_id`) ou, em último caso, estorno/ajuste
  manual (`apps/edge-api`, sempre revisado por humano). É o único terminal
  pós-débito — todos os outros (`expired`, `denied`, `confirmation_timeout`,
  `cancelled`) ocorrem sempre antes de qualquer `ledger_entry` existir.

## Máquina de estados — `interaction_request` (servidor)

```text
(none) --sighting autenticado, interaction_id novo--> discovered
discovered --validado e publicado na fila--> queued
discovered --display_code colide com interação ativa--> discovered (retido, não publicado até a 1ª resolver)
discovered --expires_at_local atingido antes de publicar--> expired

queued --claim CAS bem-sucedido--> claimed
queued --expires_at_local atingido sem claim--> expired
queued --cancelamento do operador--> cancelled

claimed --transaction_intent criado, desafio GATT enviado--> awaiting_band_confirmation
claimed --lease expira por falha de rádio, tentativa < 3--> queued   [retry com novo challenge_nonce]
claimed --lease expira, 3ª tentativa esgotada--> expired
claimed --cancelamento do operador--> cancelled

awaiting_band_confirmation --band_auth_tag válido--> confirmed_pending_validation
awaiting_band_confirmation --10s sem clique--> confirmation_timeout
awaiting_band_confirmation --cancelamento do operador (vence corrida com a decisão)--> cancelled

confirmed_pending_validation --saldo e regras válidos--> authorized
confirmed_pending_validation --saldo insuficiente ou regra violada--> denied

authorized --ledger_entry criado--> authorized (débito ocorre aqui, antes do acionamento)
authorized --acionamento automático confirmado--> completed
authorized --acionamento automático falha--> actuation_failed
actuation_failed --override manual do operador confirmado--> completed
actuation_failed --estorno/ajuste manual (último recurso)--> actuation_failed  [encerrado operacionalmente, fora do ledger automático]
```

Estados terminais: `completed`, `expired`, `denied`, `confirmation_timeout`,
`cancelled`. `actuation_failed` é um estado de espera operacional, não
terminal por si só — só se resolve por override manual (→ `completed`) ou por
processo administrativo de estorno/ajuste fora do fluxo automático.

Não existe gesto explícito de rejeição pela pessoa (ADR 0003) — a única
saída de `awaiting_band_confirmation` por inação é o timeout de 10s. Mas
existe uma recusa distinta, disparada pelo **servidor**, não pela pessoa:
depois que a pessoa confirma e o `band_auth_tag` é validado
(`confirmed_pending_validation`), o servidor ainda valida saldo e regras
(`transaction-flow.md`, passo 12) antes de criar o `ledger_entry`. Se o
saldo for insuficiente ou uma regra for violada, a interação vai para
`denied` — sem débito, resultado enviado à pulseira imediatamente (não há
acionamento a esperar, porque nada foi debitado). Esse é o cenário "saldo
insuficiente" de `tests/e2e/README.md`, e é diferente do `actuation_failed`
(que ocorre depois do débito).

Regra de corrida (ADR 0003): um cancelamento do operador só é aceito
enquanto a transação não tiver alcançado `ledger_entry`. Cancelamento
chegando após o débito é rejeitado como no-op.

## Máquina de estados — pulseira (protocolo BLE)

Fonte: `contracts/proximity/README.md` + ADR 0003.

```text
idle --pressão longa--> advertising_request
advertising_request --continua anunciando (sem sinal distinto de "na fila")--> queued
queued --desafio GATT recebido--> awaiting_confirmation
awaiting_confirmation --clique curto--> confirming
awaiting_confirmation --10s sem clique--> timeout   [processo reinicia; interação não é reaproveitada]
confirming --resultado recebido, result=denied (saldo/regra)--> denied     [imediato, nada a esperar]
confirming --resultado recebido, result=completed (após acionamento confirmado)--> completed
```

`queued` é um estado de UI local, sem sinal distinto do servidor —
indistinguível de `advertising_request` até o desafio GATT chegar
(advertising é unidirecional). Não existe estado de pulseira para
`actuation_failed`/`cancelled`: o resultado de sucesso só é enviado depois
que o acionamento é confirmado (automático ou override manual), então a
pulseira nunca fica sabendo de uma falha intermediária de acionamento — ela
permanece em `confirming` até o resultado chegar, sem timeout de protocolo
nessa espera (ver ADR 0003). Já uma negação por saldo/regra (`denied`) não
depende de acionamento e é enviada assim que o servidor decide, sem espera.
Se a pessoa não recebe nenhum sinal de rádio por tempo suficiente em
`advertising_request`, a pulseira exibe localmente um aviso de
"aproxime-se" (heurística local, sem mensagem de servidor).

## Mapeamento servidor ↔ pulseira

| Servidor (`interaction_request`)   | Pulseira (protocolo)   | Observação |
|---|---|---|
| (none)                              | `idle`                 | — |
| `discovered`                        | `advertising_request`  | inclui o caso retido por colisão de `display_code`; pulseira não é avisada |
| `queued` / `claimed`                | `queued`                | pulseira não distingue os dois; só percebe mudança quando chega o desafio GATT |
| `awaiting_band_confirmation`        | `awaiting_confirmation` → `confirming` | pulseira entra em `confirming` só após o clique |
| `confirmed_pending_validation`       | `confirming`             | servidor valida saldo/regras; pulseira apenas espera |
| `denied`                              | `denied`                 | saldo insuficiente ou regra violada; resultado enviado de imediato, sem débito |
| `authorized` (aguardando acionamento) | `confirming`           | pulseira segue esperando; resultado de sucesso não foi liberado ainda |
| `completed`                          | `completed`              | só depois que acionamento (automático ou override) é confirmado |
| `confirmation_timeout`              | `timeout`                | processo reinicia; nova pressão longa cria novo `interaction_id` |
| `cancelled`                          | permanece em `confirming` até seu próprio timeout local, ou volta a `advertising_request` se cancelado antes do desafio | pulseira não recebe sinal específico de cancelamento além do fim do desafio |
| `actuation_failed`                   | permanece em `confirming` | resultado de sucesso só chega quando override manual resolver, ou nunca (caso de estorno) |

## Referência

Todas as decisões que fecham este modelo (criptografia, timeouts, gestos,
ordem débito/acionamento, retry, colisão de código) estão em
[ADR 0003](../decisions/0003-ble-protocol-parameters.md). O catálogo de
invariantes cruzado com este modelo está em
[domain-invariants.md](domain-invariants.md).
