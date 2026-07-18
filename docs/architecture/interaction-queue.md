# Fila global de interações

## Objetivo

Consolidar solicitações BLE capturadas por vários gateways e permitir que o
operador da atração correta escolha o código verbalizado pela pessoa.

## Entidades

```text
interaction_request
interaction_sighting
interaction_claim
transaction_intent
```

## Estados

```text
discovered
queued
claimed
awaiting_band_confirmation
confirmed_pending_validation
credit_reserved
actuation_pending
completed
```

Saídas: `expired`, `denied`, `confirmation_timeout`, `actuation_failed`,
`reconciliation_required` e `cancelled`. `denied` é a validação de saldo/regras do servidor após a
confirmação da pessoa — não um gesto da pulseira (ADR 0003). Máquina de
estados completa e verificada em
[domain-model.md](domain-model.md).

## Regras

- sightings idênticos são consolidados por `interaction_id`
- novos códigos aparecem no topo da fila
- seleção usa ID estável, nunca posição da linha
- uma interação possui no máximo um claim ativo
- claim possui lease e expira se o rádio falhar
- a sessão do operador é vinculada ao gateway físico; o corpo da requisição
  não pode substituir essa identidade
- uma pulseira possui no máximo uma interação ativa
- código visual duplicado publica ambas as entradas como ambíguas, bloqueia
  claim e orienta regeneração; nenhuma solicitação fica invisível
- payload inválido não é exibido
- todos os TFTs recebem a mesma visão lógica da fila

## Concorrência

O claim deve ser realizado por compare-and-swap no banco. Dois operadores nunca
podem avançar a mesma interação. Falha de rádio pode liberar o lease para retry,
mas não cria um segundo `transaction_id` depois da confirmação.

O claim, o lease inicial de 10 segundos, o `transaction_intent` em estado
`claimed` e o evento de outbox nascem na mesma transação PostgreSQL. A ausência
de rádio recente não altera a interação.

## Gateways

- `operator_gateway_id`: origem da seleção e da atribuição da atração.
- `radio_gateway_id`: melhor ponte BLE disponível entre sightings recentes.

"Recente" significa `received_at` do servidor nos últimos 10 segundos. A ponte
é escolhida por RSSI decrescente, recência decrescente e menor ID de protocolo
como desempate. O relógio informado pelo gateway não participa da decisão.

Ambos são auditados, mas apenas o gateway operador determina a métrica de uso da
atração.
