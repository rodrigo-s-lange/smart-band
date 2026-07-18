# ADR 0009 — Claim atômico e seleção do gateway de rádio

Status: aceita — 2026-07-18

## Contexto

Todos os gateways reportam sightings autenticados para uma fila global. O
terminal que recebe a escolha do operador não é necessariamente a melhor ponte
BLE até a pulseira. Também não é aceitável que dois operadores avancem a mesma
solicitação ou que uma sessão de operador declare arbitrariamente outro
gateway.

## Decisão

O PostgreSQL executa, em uma única transação, o compare-and-swap de `queued`
para `claimed`, a criação de `interaction_claim` e `transaction_intent`, a
escolha do gateway de rádio e a publicação de `interaction.claimed` no outbox.

- A sessão do operador fica vinculada a um `gateway_id` e `site_id`. O
  `operator_gateway_id` do pedido deve coincidir com esse vínculo.
- O gateway operador precisa estar ativo e associado à atração selecionada.
- Somente sightings recebidos pelo relógio do servidor nos 10 segundos
  anteriores ao claim são elegíveis.
- A escolha ordena por maior RSSI, depois por `received_at` mais recente e,
  como desempate determinístico, menor `gateway.protocol_id`.
- O gateway de rádio pode ser o próprio gateway operador.
- Sem sighting recente, nenhuma linha de claim/transação é criada e a API
  retorna conflito `no_radio_gateway`.
- O lease inicial dura 10 segundos e cobre conexão BLE e despacho do desafio.
  A janela posterior de 10 segundos para o clique começa somente após o envio
  bem-sucedido do Challenge GATT.
- O `transaction_intent` nasce em `claimed`, com custo atual da atração,
  carteira da sessão ativa, `transaction_id` aleatório de 8 bytes e
  `challenge_nonce` aleatório de 8 bytes.
- Colisão do identificador aleatório é repetida até três vezes pela aplicação.

## Concorrência e falhas

A linha de `interaction_requests` é bloqueada antes das validações mutáveis.
Somente o primeiro concorrente observa `queued`; os demais recebem conflito.
Falhas de validação, ausência de carteira ou de rádio não deixam claim parcial.
`interaction.confirmation_requested` ainda não é emitido nesta operação: esse
evento pertence ao despacho GATT da próxima fatia.

## Migração

Sessões de operador anteriores não possuem vínculo comprovável com gateway e
são invalidadas, exigindo novo login. Desafios legados ativos de 16 bytes são
cancelados e seus claims liberados antes da conversão do schema para os 8 bytes
definidos no contrato BLE; desafios históricos são reduzidos apenas para
compatibilidade estrutural.

## Consequências

A seleção é reproduzível e auditável, operador e rádio continuam sendo papéis
distintos e a appliance permanece a única autoridade. RSSI é uma heurística de
ponte, não prova de distância; métricas futuras podem alterar a política por
novo ADR sem mudar o contrato do claim.
