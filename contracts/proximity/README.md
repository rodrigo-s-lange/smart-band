# Protocolo de proximidade BLE

Contrato lógico entre pulseira, gateways e servidor local.

## Princípios

- advertising descobre solicitações; não autoriza transações
- GATT transporta desafio, confirmação e resultado
- código visual é seletor humano, não credencial suficiente
- identificador permanente não aparece no ar
- servidor local valida todas as provas criptográficas
- gateway não armazena chaves de pulseira

## Solicitação

Após pressão longa, a pulseira cria:

```text
protocol_version
session_nonce
tag                 # AES-CMAC(band_key, session_nonce ‖ display_code ‖ expires_at_local ‖ transaction_counter), autentica e resolve identidade (ADR 0003, ADR 0004)
display_code
expires_at_local    # offset relativo, 60s (ADR 0004)
```

`interaction_id` não é gerado nem anunciado pela pulseira — o servidor
atribui um `interaction_id` na primeira vez que resolve um `session_nonce`
novo (ver "Descoberta"). `ephemeral_id` e `auth_tag` foram unificados no
campo `tag` único para caber no orçamento de bytes do advertising legado
(ADR 0004). Layout binário exato (offsets, tamanhos) em
[binary-format.md](binary-format.md).

O código visual usa Crockford Base32, agrupado como `M7K-3PX`.

## Descoberta

Gateways enviam ao servidor:

```text
interaction_payload
gateway_id
rssi
received_at
```

O servidor resolve a identidade da pulseira testando as chaves das
pulseiras ativas na sessão do evento contra o `session_nonce` recebido, até
reproduzir o `tag` informado (ver ADR 0003). Na primeira vez que resolve um
`session_nonce` novo, o servidor atribui um `interaction_id` e cria a
`interaction_request`; sightings seguintes são correlacionados pelo próprio
`session_nonce` bruto, sem precisar de um ID pré-anunciado (ADR 0004).

## Seleção e claim

O operador escolhe o código no gateway da atração. O servidor executa claim
atômico e registra `operator_gateway_id`. Em seguida escolhe um
`radio_gateway_id` entre os sightings recentes.

## Confirmação GATT

Desafio lógico:

```text
protocol_version
transaction_id
challenge_nonce
interaction_id
attraction_id
operator_gateway_id
amount
server_auth_tag
```

Não há campo `expires_at` no desafio: a janela de confirmação é a constante
fixa de 10s do protocolo (ADR 0003), conhecida de antemão pela pulseira —
transmiti-la a cada desafio seria redundante e daria a um gateway malicioso
uma forma de tentar manipular a janela. A pulseira inicia seu próprio
temporizador de 10s ao receber o desafio.

A pulseira exibe atração e custo. Clique curto confirma; não existe gesto
explícito de rejeição — 10s sem clique é o único caminho de recusa, e reinicia
o processo (a interação não é reaproveitada; ver ADR 0003). Um comando
`Cancel` distinto (gateway → pulseira, ver
[binary-format.md](binary-format.md)) permite ao operador cancelar mesmo
depois do desafio ter sido enviado.

Resposta autenticada candidata:

```text
protocol_version
transaction_id
interaction_id
decision
transaction_counter
band_auth_tag
```

O `band_auth_tag` autentica todos os campos relevantes do desafio e da decisão.

## Resultado

O débito ocorre no commit do ledger, mas o servidor só envia o resultado à
pulseira depois que o acionamento da atração é confirmado — automático ou
por override manual do operador (ver ADR 0003). A pulseira permanece em
`confirming` até então, sem timeout de protocolo nessa espera:

```text
transaction_id
result              # 0=negado por saldo, 1=negado por regra, 2=concluído
remaining_balance
result_auth_tag
```

A pulseira só atualiza o saldo visual depois de validar o resultado. Não
existe valor de `result` para `actuation_failed`: enquanto não resolvido
(override manual ou estorno), nenhum resultado é escrito — a pulseira
permanece aguardando.

## Estados

```text
idle
advertising_request
queued
awaiting_confirmation
confirming
denied
completed
timeout
```

Não há estado de pulseira disparado por gesto de rejeição (não existe esse
gesto, ADR 0003). `denied` é enviado pelo servidor quando saldo ou regras
não permitem a transação — descoberto só depois que a pessoa confirma
(`transaction-flow.md`, passo 12) — e chega imediatamente, sem esperar
acionamento, porque nada foi debitado. O resultado de **sucesso**
(`completed`) é o único que espera a confirmação do acionamento; a pulseira
nunca fica sabendo de uma falha intermediária de acionamento (ver ADR 0003 e
`docs/architecture/domain-model.md`).

## Parâmetros congelados

Todos os parâmetros abaixo foram fechados em
[ADR 0003](../../docs/decisions/0003-ble-protocol-parameters.md) e
[ADR 0004](../../docs/decisions/0004-advertising-payload-and-transport.md):

- formato binário fixo, little-endian
- AES-128-CMAC truncada para 64 bits em todos os payloads autenticados
- contador de replay persistido na NVS a cada incremento
- timeouts fixos no protocolo (janela de confirmação: 10s)
- sem gesto explícito de rejeição; ausência de clique = timeout
- cancelamento do operador a qualquer momento, via novo comando GATT
- débito antes do acionamento; falha de acionamento resolvida por override
  manual do operador, nunca por reversão automática
- aviso de baixa conectividade ("aproxime-se") é heurística local da pulseira
- até 3 tentativas de retry do lease, uma por `challenge_nonce`
- colisão de `display_code` resolvida por retenção de publicação no servidor
- resolução de identidade: `tag = AES-CMAC(band_key, ...)`, busca por chave entre pulseiras ativas na sessão
- payload de advertising unificado em 22 bytes; `interaction_id` atribuído pelo servidor, não anunciado
- expiração da fase de descoberta: 60s (offset relativo, distinto dos 10s de confirmação)
- transporte de tempo real da fila: Server-Sent Events

- características e UUIDs GATT: definidos em
  [binary-format.md](binary-format.md)

## Parâmetros ainda não congelados

- identidade individual de operador (mantido `operator_gateway_id` por ora)
- store-and-forward do ack de acionamento no firmware do gateway (Etapa 10)

Layout binário completo (offsets, tamanhos, UUIDs) em
[binary-format.md](binary-format.md). Vetores de teste em
[test-vectors.md](test-vectors.md). Detalhamento completo das decisões e da
motivação nas ADRs [0003](../../docs/decisions/0003-ble-protocol-parameters.md)
e [0004](../../docs/decisions/0004-advertising-payload-and-transport.md).
