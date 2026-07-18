# Vetores de teste do protocolo BLE

Calculados com `cryptography.hazmat.primitives.cmac.CMAC`. Truncamento sempre
usa os oito bytes mais significativos. Chave de teste:
`2b7e151628aed2a6abf7158809cf4f3c`.

## Sanity check RFC 4493

```text
message = 6bc1bee22e409f96e93d7e117393172a
CMAC    = 070a16b46b4d4144f79bdd9dd04a287c
```

## Advertising

```text
protocol_version    = 01
session_nonce       = 0102030405060708
display_code_LE     = 78563412
request_ttl_seconds = 3c
CMAC input          = 01 01 0102030405060708 78563412 3c
                    = 01010102030405060708785634123c
full CMAC           = 5317788fcfee63d0c9ffd21bdc8bf0f7
tag                 = 5317788fcfee63d0
payload (22B)       = 0101020304050607085317788fcfee63d0785634123c
```

Busca de identidade para a mesma entrada:

```text
000102030405060708090a0b0c0d0e0f -> bc4058dde92dd76b
2b7e151628aed2a6abf7158809cf4f3c -> 5317788fcfee63d0 MATCH
ffeeddccbbaa99887766554433221100 -> 93f4aa6a09373ab1
```

Alterar `display_code` para `0x12345679` produz `8720d885197edfeb`; manter a
tag original deve rejeitar o payload.

## Challenge

```text
transaction_id      = aabbccddeeff0011
challenge_nonce     = 1122334455667788
interaction_id_LE   = 01000000
attraction_id_LE    = 0700
operator_gateway_LE = 0300
amount_LE           = dc050000
CMAC input          = 0201aabbccddeeff001111223344556677880100000007000300dc050000
server_auth_tag     = 69521d189b105519
payload (37B)       = 01aabbccddeeff001111223344556677880100000007000300dc05000069521d189b105519
```

## Decision vinculada ao Challenge

```text
decision            = 01
transaction_counter = 2b000000
CMAC input          = 0301aabbccddeeff001111223344556677880100000007000300dc050000012b000000
band_auth_tag       = 7bd168f8308d9643
payload (26B)       = 01aabbccddeeff001101000000012b0000007bd168f8308d9643
```

Se apenas o custo do Challenge mudar de 1500 para 1501, a tag esperada passa
a `ce72ba9a8a98ae7e`. Portanto a tag original deve ser rejeitada mesmo que o
payload curto da Decision permaneça igual.

## Result

```text
CMAC input      = 0401aabbccddeeff00110234210000
result_auth_tag = e2f6ddf09c0797c7
payload (22B)   = 01aabbccddeeff00110234210000e2f6ddf09c0797c7
```

## Cancel

```text
CMAC input      = 0501aabbccddeeff0011
server_auth_tag = b8ccd465710441cb
payload (17B)   = 01aabbccddeeff0011b8ccd465710441cb
```

## Propriedades obrigatórias

- trocar o byte de domínio deve mudar a tag;
- alterar qualquer campo da transcrição Decision deve invalidar a resposta;
- repetir `(band_id, session_nonce)` deve recuperar a interação original sem
  estender `expires_at`;
- contador Decision igual ou menor que o último aceito deve ser rejeitado.
