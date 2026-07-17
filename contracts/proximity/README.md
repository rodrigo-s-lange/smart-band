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
interaction_id
session_nonce
ephemeral_id
auth_tag
display_code
expires_at_local
```

O advertising precisa caber no formato legado suportado pelos gateways do MVP.
O código visual usa Crockford Base32, agrupado como `M7K-3PX`.

## Descoberta

Gateways enviam ao servidor:

```text
interaction_payload
gateway_id
rssi
received_at
```

O servidor autentica, resolve a pulseira e deduplica por `interaction_id`.

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
expires_at
server_auth_tag
```

A pulseira exibe atração e custo. Clique curto confirma; timeout cancela.

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

Após commit do ledger, o servidor envia:

```text
transaction_id
result
remaining_balance
result_auth_tag
```

A pulseira só atualiza o saldo visual depois de validar o resultado.

## Estados

```text
idle
advertising_request
queued
awaiting_confirmation
confirming
completed
rejected
timeout
```

## Parâmetros ainda não congelados

- formato binário e endianness
- algoritmo e tamanho final das tags
- características e UUIDs GATT
- intervalos e timeouts
- persistência do contador
- gesto explícito de rejeição

Esses parâmetros exigem ADR e vetores de teste antes da implementação física.
