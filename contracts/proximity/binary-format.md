# Layout binário do protocolo BLE

Formato vigente após a ADR 0005. Multi-byte é little-endian. Tags são os oito
bytes mais significativos de AES-128-CMAC. O byte de domínio é entrada
implícita do CMAC e não integra o payload no fio.

## Advertising — Solicitação (22 bytes)

| Offset | Campo | Tipo | Bytes |
|---|---|---|---:|
| 0 | `protocol_version` | uint8 | 1 |
| 1 | `session_nonce` | bytes | 8 |
| 9 | `tag` | bytes | 8 |
| 17 | `display_code` | uint32 LE | 4 |
| 21 | `request_ttl_seconds` | uint8 | 1 |

`display_code` usa exatamente seis símbolos Crockford Base32, exibidos como
`XXX-XXX`. Os dois bits superiores do `uint32` são reservados e precisam ser
zero; valores fora de `0..2^30-1` são inválidos.

```text
tag_input = 0x01 || protocol_version || session_nonce ||
            display_code_LE || request_ttl_seconds
```

Encapsulamento: Flags 3B + Manufacturer Data 26B = 29B, dentro do limite
legacy de 31B. Repetições do mesmo nonce não estendem o TTL.

## Serviço GATT

| Elemento | UUID |
|---|---|
| Serviço | `73b8a100-0001-4a5e-8f3d-2c9e6b7a1000` |
| Challenge (Write) | `73b8a100-0002-4a5e-8f3d-2c9e6b7a1000` |
| Decision (Notify) | `73b8a100-0003-4a5e-8f3d-2c9e6b7a1000` |
| Result (Write) | `73b8a100-0004-4a5e-8f3d-2c9e6b7a1000` |
| Cancel (Write) | `73b8a100-0005-4a5e-8f3d-2c9e6b7a1000` |

Pulseira é peripheral/GATT server; gateway é central/GATT client. Negociar
ATT MTU ≥ 64 para o Challenge de 37 bytes.

## Challenge (37 bytes)

| Offset | Campo | Tipo | Bytes |
|---|---|---|---:|
| 0 | `protocol_version` | uint8 | 1 |
| 1 | `transaction_id` | bytes | 8 |
| 9 | `challenge_nonce` | bytes | 8 |
| 17 | `interaction_id` | uint32 LE | 4 |
| 21 | `attraction_id` | uint16 LE | 2 |
| 23 | `operator_gateway_id` | uint16 LE | 2 |
| 25 | `amount` | uint32 LE | 4 |
| 29 | `server_auth_tag` | bytes | 8 |

`server_auth_tag = CMAC64(band_key, 0x02 || bytes[0..28])`.

## Decision (26 bytes)

| Offset | Campo | Tipo | Bytes |
|---|---|---|---:|
| 0 | `protocol_version` | uint8 | 1 |
| 1 | `transaction_id` | bytes | 8 |
| 9 | `interaction_id` | uint32 LE | 4 |
| 13 | `decision` | uint8 | 1 |
| 14 | `transaction_counter` | uint32 LE | 4 |
| 18 | `band_auth_tag` | bytes | 8 |

Entrada canônica — o servidor reconstrói os campos do Challenge persistido:

```text
0x03 || protocol_version || transaction_id || challenge_nonce ||
interaction_id || attraction_id || operator_gateway_id || amount ||
decision || transaction_counter
```

## Result (22 bytes)

| Offset | Campo | Tipo | Bytes |
|---|---|---|---:|
| 0 | `protocol_version` | uint8 | 1 |
| 1 | `transaction_id` | bytes | 8 |
| 9 | `result` | uint8 | 1 |
| 10 | `remaining_balance` | uint32 LE | 4 |
| 14 | `result_auth_tag` | bytes | 8 |

Resultados: `0` saldo insuficiente, `1` regra violada, `2` concluído. CMAC:
`0x04 || bytes[0..13]`.

## Cancel (17 bytes)

| Offset | Campo | Tipo | Bytes |
|---|---|---|---:|
| 0 | `protocol_version` | uint8 | 1 |
| 1 | `transaction_id` | bytes | 8 |
| 9 | `server_auth_tag` | bytes | 8 |

CMAC: `0x05 || bytes[0..8]`. Cancel válido move a pulseira de
`awaiting_confirmation`, `confirming` ou `attention_required` para
`cancelled`.
