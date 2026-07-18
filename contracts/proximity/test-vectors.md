# Vetores de teste do protocolo BLE

Valores de AES-128-CMAC calculados de verdade (biblioteca `cryptography`,
Python), não fabricados — usados para validar qualquer implementação
(firmware, simuladores, backend) contra um resultado conhecido. Convenção:
truncamento para 64 bits sempre pega os **8 bytes mais significativos**
(leftmost) da saída de 128 bits do AES-CMAC.

## Sanity check — RFC 4493 Example 2

Confirma que a implementação de AES-CMAC usada está correta antes de
confiar em qualquer vetor abaixo (chave e mensagem padrão da RFC, saída de
128 bits, sem truncamento):

```text
key     = 2b7e151628aed2a6abf7158809cf4f3c
message = 6bc1bee22e409f96e93d7e117393172a
AES-CMAC = 070a16b46b4d4144f79bdd9dd04a287c
```

Qualquer implementação deve reproduzir exatamente essa saída antes de
prosseguir para os vetores específicos do protocolo.

## Chave de pulseira usada nos vetores abaixo

```text
band_key = 2b7e151628aed2a6abf7158809cf4f3c
```

(reaproveita a chave de teste da RFC 4493 — não é uma chave de produção.)

## 1. Advertising — Solicitação válida

Entrada:

```text
session_nonce       = 0102030405060708
display_code (u32)  = 0x12345678   (Crockford Base32: 28T-5CY-0)
expires_at_local     = 60  (0x3c)
transaction_counter  = 42  (0x2a000000 LE)
```

CMAC:

```text
CMAC input (17B) = session_nonce ‖ display_code_LE ‖ expires_at_local ‖ transaction_counter_LE
                  = 0102030405060708785634123c2a000000
full CMAC (16B)  = a220c576f07101988f29ab553a75a93e
tag (8B, leftmost) = a220c576f0710198
```

Payload de advertising completo (22 bytes,
`protocol_version ‖ session_nonce ‖ tag ‖ display_code_LE ‖ expires_at_local`):

```text
010102030405060708a220c576f0710198785634123c
```

## 2. Resolução de identidade — busca por chave

Mesmo `adv_input` acima, testado contra um pool de 3 chaves candidatas
(simulando o servidor buscando qual pulseira provisionada corresponde ao
`session_nonce` recebido):

```text
candidate[0] = 000102030405060708090a0b0c0d0e0f -> tag=43051d4d0aae868c (no match)
candidate[1] = 2b7e151628aed2a6abf7158809cf4f3c -> tag=a220c576f0710198 (MATCH)
candidate[2] = ffeeddccbbaa99887766554433221100 -> tag=f47f10941b4ebefc (no match)
```

Implementações de referência devem iterar até achar `candidate[1]` e parar
ali — a comparação de cada tentativa deve ser em tempo constante (AGENTS.md).

## 3. Caso inválido — payload adulterado

Mesmo cenário do item 1, mas com um único bit invertido em `display_code`
(`0x12345678` → `0x12345679`) mantendo o `tag` original — simula um
gateway ou atacante alterando o payload em trânsito:

```text
display_code adulterado = 0x12345679
tag recebido (original)  = a220c576f0710198
tag recalculado           = cc6cbf644bcf528a
resultado esperado        = MISMATCH -> payload rejeitado (I6: advertising inválido não entra na fila)
```

## 4. GATT Challenge (servidor → pulseira)

Entrada:

```text
transaction_id       = aabbccddeeff0011
challenge_nonce      = 1122334455667788
interaction_id       = 1
attraction_id        = 7
operator_gateway_id  = 3
amount (cents)       = 1500
```

```text
CMAC input (29B) = 01aabbccddeeff001111223344556677880100000007000300dc050000
server_auth_tag  = 376e39a5624f124b
payload completo (37B) = 01aabbccddeeff001111223344556677880100000007000300dc050000376e39a5624f124b
```

## 5. GATT Decision (pulseira → servidor)

Entrada:

```text
transaction_id       = aabbccddeeff0011  (mesmo do item 4)
interaction_id       = 1
decision             = 1  (confirmado)
transaction_counter  = 43
```

```text
CMAC input (18B) = 01aabbccddeeff001101000000012b000000
band_auth_tag    = b6e47b128ece1137
payload completo (26B) = 01aabbccddeeff001101000000012b000000b6e47b128ece1137
```

## 6. GATT Result (servidor → pulseira)

Entrada:

```text
transaction_id     = aabbccddeeff0011
result              = 2  (concluído com sucesso)
remaining_balance   = 8500 (cents)
```

```text
CMAC input (13B)  = aabbccddeeff00110234210000
result_auth_tag   = 7ac5f8f80bba87fa
payload completo (21B) = aabbccddeeff001102342100007ac5f8f80bba87fa
```

## 7. GATT Cancel (servidor → pulseira)

Entrada:

```text
transaction_id = aabbccddeeff0011
```

```text
CMAC input (9B) = 01aabbccddeeff0011
server_auth_tag = a8317eeb88f2ae8c
payload completo (17B) = 01aabbccddeeff0011a8317eeb88f2ae8c
```

## Reprodutibilidade

Vetores gerados com `cryptography.hazmat.primitives.cmac.CMAC` (Python) —
qualquer outra implementação de AES-128-CMAC (mbedTLS no firmware ESP-IDF,
`aes-cmac` no backend, etc.) deve reproduzir exatamente os mesmos bytes para
as mesmas entradas. Divergência indica erro de ordenação de bytes
(endianness), erro de concatenação dos campos de entrada, ou truncamento no
lado errado (deve ser sempre os 8 bytes mais significativos).
