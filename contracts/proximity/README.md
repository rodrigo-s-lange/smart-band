# Protocolo de proximidade BLE

Contrato lógico vigente entre pulseira, gateways e appliance local. A
[ADR 0005](../../docs/decisions/0005-protocol-correction-and-transaction-safety.md)
prevalece sobre trechos conflitantes das ADRs 0003/0004.

## Princípios

- advertising descobre e autentica solicitações; não autoriza consumo
- GATT transporta desafio, confirmação, resultado e cancelamento
- código visual é seletor humano, nunca credencial financeira
- identificador permanente e chave da pulseira não passam pelo gateway
- appliance valida as provas e mantém saldo, reserva e ledger

## Solicitação e descoberta

```text
protocol_version
session_nonce          # 64 bits aleatórios por solicitação
tag                    # CMAC domínio 0x01; não inclui campo oculto
display_code
request_ttl_seconds    # 60s
```

O servidor testa as chaves das pulseiras ativas até reproduzir `tag`, usando
comparação constante. Depois persiste `(band_id, session_nonce)` como único,
atribui `interaction_id` e calcula `expires_at` a partir do primeiro sighting
autenticado. Replays apenas acrescentam sightings; nunca recriam ou renovam a
interação.

Código Crockford Base32 é exibido como `M7K-3PX`. Colisões ficam visíveis como
ambíguas e bloqueiam claim até uma pessoa gerar nova solicitação.

## Confirmação GATT

Challenge contém versão, transação, `challenge_nonce`, interação, atração,
gateway operador, valor e `server_auth_tag`. A pulseira mostra atração e custo
e aceita clique curto durante 10 segundos.

Decision transmite somente os campos necessários no fio, mas o
`band_auth_tag` cobre a transcrição completa do Challenge mais `decision` e
`transaction_counter`. Alterar custo, atração, nonce ou gateway invalida a
confirmação.

## Reserva, acionamento e resultado

Uma confirmação válida cria reserva de crédito, não débito. O servidor gera
`actuation_command_id`; o gateway persiste e executa esse ID no máximo uma
vez. Ack positivo converte reserva em débito e produz Result `completed`.

Ack `not_executed` ou ambíguo não cria débito. Ele exige retry/resolução auditada
ou liberação comprovada da reserva. Override e reconciliação exigem `operator_id` e
`operator_gateway_id`.

Após o clique, a pulseira mostra progresso por até 30 segundos. Sem resultado,
entra em `attention_required`, exibe “PROCURE OPERADOR” e mantém a mesma
solicitação conectável para receber Result/Cancel tardio.

## Estados da pulseira

```text
idle
advertising_request
awaiting_confirmation
confirming
attention_required
denied
completed
cancelled
timeout
```

## Parâmetros vigentes

- wire format binário little-endian
- AES-128-CMAC truncado aos 8 bytes mais significativos
- bytes de domínio: advertising `0x01`, challenge `0x02`, decision `0x03`, result `0x04`, cancel `0x05`
- solicitação: 60s desde o primeiro sighting autenticado
- confirmação: 10s
- progresso após confirmação: 30s antes de `attention_required`
- até 3 tentativas de gateway de rádio, cada uma com novo `challenge_nonce`
- fila em tempo real por SSE
- contador monotônico somente na Decision, persistido antes do uso
- GATT e vetores: [binary-format.md](binary-format.md) e [test-vectors.md](test-vectors.md)
