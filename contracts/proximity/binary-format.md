# Layout binário do protocolo BLE

Formato final de fio para advertising e GATT, decorrente das ADRs 0003 e
0004. Todos os campos multi-byte são little-endian (ADR 0003). Todos os
identificadores de 8 bytes (`tag`, `challenge_nonce`, `server_auth_tag`,
`band_auth_tag`, `result_auth_tag`) são truncamentos de 64 bits de
AES-128-CMAC, por decisão da ADR 0003.

## Advertising — Solicitação (22 bytes)

| Offset | Campo | Tipo | Bytes | Observação |
|---|---|---|---|---|
| 0 | `protocol_version` | uint8 | 1 | `1` nesta versão |
| 1 | `session_nonce` | bytes | 8 | gerado pela pulseira a cada solicitação |
| 9 | `tag` | bytes | 8 | `AES-CMAC(band_key, session_nonce ‖ display_code ‖ expires_at_local ‖ transaction_counter)` truncado; resolve identidade e autentica (ADR 0003/0004) |
| 17 | `display_code` | uint32 LE | 4 | renderizado como Crockford Base32 agrupado (`M7K-3PX`) |
| 21 | `expires_at_local` | uint8 | 1 | offset relativo em segundos; `60` (ADR 0004) |

**Total: 22 bytes.** `interaction_id` não trafega no advertising — o
servidor o atribui na primeira resolução de um `session_nonce` novo (ADR
0004).

### Encapsulamento AD (legacy advertising, limite de 31 bytes)

```text
AD Flags:                3 bytes  (comprimento fixo)
AD Manufacturer Data:     1 (length) + 1 (type 0xFF) + 2 (Company ID) + 22 (payload) = 26 bytes
Total no ar:              29 bytes  (2 bytes de folga sobre o limite de 31)
```

O Company ID de 2 bytes usado em laboratório/simuladores deve ser um valor
reservado para testes (ex.: `0xFFFF`, reservado pelo Bluetooth SIG); a
appliance comercial precisa de um Company ID registrado antes da produção
física (Etapa 11), fora do escopo desta ADR.

## GATT — serviço e características

UUID base privado de 128 bits, fixo para esta versão do protocolo (mudança
exige nova ADR):

| Elemento | UUID |
|---|---|
| Serviço SmartBand Interaction | `73b8a100-0001-4a5e-8f3d-2c9e6b7a1000` |
| Característica Challenge (Write, gateway → pulseira) | `73b8a100-0002-4a5e-8f3d-2c9e6b7a1000` |
| Característica Decision (Notify, pulseira → gateway) | `73b8a100-0003-4a5e-8f3d-2c9e6b7a1000` |
| Característica Result (Write, gateway → pulseira) | `73b8a100-0004-4a5e-8f3d-2c9e6b7a1000` |
| Característica Cancel (Write, gateway → pulseira) | `73b8a100-0005-4a5e-8f3d-2c9e6b7a1000` |

A pulseira é sempre periférico e GATT server (papel já implícito no BLE: só
quem anuncia pode ser conectado como periférico); o gateway é central e GATT
client — conecta, escreve o desafio, assina a característica Decision via
CCCD, e escreve resultado/cancelamento quando aplicável.

Conexão deve negociar ATT MTU ≥ 64 bytes logo após conectar, para caber o
desafio (maior payload, 37 bytes) em uma escrita única sem fragmentação
(`Prepare Write`). ESP32 suporta MTU negociado até 517 bytes nativamente.

`transaction_id` usa 8 bytes (64 bits aleatórios gerados pelo servidor no
claim), não UUID de 16 bytes — 2⁶⁴ é suficiente para colisão desprezível em
qualquer volume realista de transações (limite de aniversário em ~2³²
transações, muito acima do volume esperado), e mantém os payloads GATT
menores.

### Challenge (gateway escreve, 37 bytes)

| Offset | Campo | Tipo | Bytes |
|---|---|---|---|
| 0 | `protocol_version` | uint8 | 1 |
| 1 | `transaction_id` | bytes | 8 |
| 9 | `challenge_nonce` | bytes | 8 |
| 17 | `interaction_id` | uint32 LE | 4 |
| 21 | `attraction_id` | uint16 LE | 2 |
| 23 | `operator_gateway_id` | uint16 LE | 2 |
| 25 | `amount` | uint32 LE | 4 | unidade mínima da moeda (ex.: centavos) |
| 29 | `server_auth_tag` | bytes | 8 |

**Nota de simplificação:** o campo `expires_at` do desafio, listado
originalmente em `README.md`, foi removido. A janela de confirmação é uma
constante fixa de 10s do protocolo (ADR 0003), conhecida de antemão pelo
firmware da pulseira — transmiti-la a cada desafio seria redundante e
abriria superfície para um gateway malicioso tentar manipular a janela. A
pulseira inicia seu temporizador de 10s a partir do recebimento do desafio,
sempre com o valor fixo do protocolo.

### Decision (pulseira notifica, 26 bytes)

| Offset | Campo | Tipo | Bytes |
|---|---|---|---|
| 0 | `protocol_version` | uint8 | 1 |
| 1 | `transaction_id` | bytes | 8 |
| 9 | `interaction_id` | uint32 LE | 4 |
| 13 | `decision` | uint8 | 1 | `1` = confirmado (único valor válido hoje; reservado para gesto explícito futuro) |
| 14 | `transaction_counter` | uint32 LE | 4 | contador monotônico persistido (ADR 0003) |
| 18 | `band_auth_tag` | bytes | 8 | autentica desafio + decisão |

### Result (gateway escreve, 21 bytes)

| Offset | Campo | Tipo | Bytes |
|---|---|---|---|
| 0 | `transaction_id` | bytes | 8 |
| 8 | `result` | uint8 | 1 | `0` = negado por saldo insuficiente; `1` = negado por regra violada; `2` = concluído com sucesso |
| 9 | `remaining_balance` | uint32 LE | 4 | saldo após o resultado (inalterado se negado) |
| 13 | `result_auth_tag` | bytes | 8 |

`result` distingue as duas origens de negação previstas em
`docs/architecture/domain-model.md` (`denied`, validado pelo servidor antes
do débito) de sucesso (`completed`, só após acionamento confirmado). Não
existe valor de resultado para `actuation_failed`: enquanto não resolvido
(override manual ou estorno), nenhum `Result` é escrito — a pulseira
permanece aguardando.

### Cancel (gateway escreve, 17 bytes) — novo, ADR 0003

| Offset | Campo | Tipo | Bytes |
|---|---|---|---|
| 0 | `protocol_version` | uint8 | 1 |
| 1 | `transaction_id` | bytes | 8 |
| 9 | `server_auth_tag` | bytes | 8 |

Só existe cancelamento por GATT quando já há `transaction_id` e conexão
ativa (a partir de `awaiting_band_confirmation`). Cancelamento antes disso
(`queued`/`claimed`) é só remoção server-side da fila — a pulseira não é
contatada, porque nenhuma conexão GATT foi aberta ainda (ver
`domain-model.md`, mapeamento servidor ↔ pulseira).

## Referência

Decisões que originam este layout: [ADR 0003](../../docs/decisions/0003-ble-protocol-parameters.md),
[ADR 0004](../../docs/decisions/0004-advertising-payload-and-transport.md).
Máquina de estados correspondente em
[domain-model.md](../../docs/architecture/domain-model.md). Vetores de teste
em [test-vectors.md](test-vectors.md).
