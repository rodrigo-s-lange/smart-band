# ADR 0012 — Retry de rádio e transporte opaco recuperável

Status: aceita — 2026-07-18

## Contexto

O payload comercial final do Challenge aguarda decisões do cliente, mas o
despacho técnico pode avançar com bytes opacos. Para isso, a fronteira de
entrega, o fallback de rádio, o fencing de resultados, o estado terminal e a
retomada após restart precisam ser inequívocos.

## Decisão

- Cada tentativa possui `dispatch_id` persistido antes de qualquer I/O, além de
  interação, transação, tentativa, rádio, nonce, versão, payload, deadline,
  status e desfecho.
- Um resultado só avança o domínio se `dispatch_id`, tentativa, nonce e lease
  continuarem vigentes. Resultado atrasado ou duplicado é auditado e ignorado.
- `delivered` exige confirmação técnica da escrita completa na pulseira alvo.
  Enfileirar, entregar ao gateway, conectar GATT ou iniciar a escrita não basta.
- A janela de confirmação começa no commit atômico do resultado `delivered`.
- A seleção usa apenas gateways ativos do mesmo site com sighting recebido pela
  appliance nos últimos 10 segundos. Prefere candidatos ainda não usados na
  transação; se todos já foram tentados, reutiliza o melhor elegível pela ordem
  RSSI, recência e menor ID.
- Sem candidato elegível, cria a próxima tentativa em `waiting_for_radio` por
  10 segundos, com rádio vazio e sem I/O. Sighting novo move para `pending`; o
  fim da janela falha como `no_radio_gateway` e consome a tentativa. Gateway
  stale nunca é usado.
- Offline, conexão malsucedida, escrita não confirmada e deadline excedido antes
  de `delivered` consomem uma tentativa.
- A passagem à próxima tentativa encerra a anterior e cria novo `dispatch_id`,
  nonce, rádio e lease na mesma transação PostgreSQL.
- Após a terceira falha, também atomicamente: interação e claim terminam
  `expired`, `transaction_intent` termina `cancelled` e a outbox publica
  `interaction.expired` com motivo `radio_attempts_exhausted`. Não pode existir
  reserva ou lançamento de ledger.
- Timer em memória não é autoridade. Um worker orientado pelo banco recupera
  despachos pendentes e leases vencidos em lotes, com locking/fencing. I/O
  ocorre fora da transação; o resultado volta por CAS do `dispatch_id` vigente.

O contrato normativo da porta está em
[radio-dispatch.md](../../contracts/gateway/radio-dispatch.md).

## Consequências

- Retry reavalia o rádio, mas não garante mudança de ID quando só há um candidato.
- Restart pode produzir processamento pelo menos uma vez, nunca dois avanços de
  estado.
- A implementação precisa persistir tentativas e possuir worker recuperável.
- Eventos técnicos de tentativa precisam ser versionados antes do consumidor.
- O payload continua opaco e nenhuma política comercial é congelada.

## Não decisão

Esta ADR não define Challenge/Decision final, preço, duração, crédito, cadastro,
pagamento, capabilities definitivas nem acionamento físico.

## Vault

Decisão correspondente no vault, commit
`ce99e8a5eb53d58b033016379e6128d71522b669`:

```text
07-decisoes/2026-07-18-smart-band-semantica-retry-radio-transporte-opaco.md
```
