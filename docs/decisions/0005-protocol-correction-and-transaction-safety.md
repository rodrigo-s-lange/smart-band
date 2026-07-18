# ADR 0005 — Correção do protocolo e segurança transacional

Status: parcialmente substituída pela ADR 0010 — 2026-07-18

A segurança transacional continua vigente. A exigência de identidade humana
individual em exceções foi substituída pela identidade do gateway cadastrado.

Substitui parcialmente as ADRs 0003 e 0004 nos pontos de advertising,
autenticação das mensagens, replay, ordem entre débito e acionamento,
cancelamento, colisão de código e auditoria de exceções.

## Contexto

A revisão dos contratos executáveis encontrou duas inconsistências que
impediam uma implementação segura:

1. o `tag` do advertising incluía `transaction_counter`, mas esse contador
   não trafegava no payload de 22 bytes; portanto o servidor não conseguiria
   recalcular o CMAC durante a busca de identidade;
2. o `band_auth_tag` da mensagem `Decision` não cobria o `challenge_nonce`, a
   atração e o custo exibidos, apesar de o domínio exigir esse vínculo.

A mesma revisão identificou risco de débito sem entrega quando o ledger era
commitado antes da confirmação física do acionamento.

## Decisão

### Advertising implementável em 22 bytes

O payload continua com 22 bytes:

```text
protocol_version    1 byte
session_nonce       8 bytes
tag                 8 bytes
display_code        4 bytes
request_ttl_seconds 1 byte
```

O CMAC não inclui contador oculto:

```text
tag = truncate64(AES-CMAC(
  band_key,
  0x01 || protocol_version || session_nonce ||
  display_code_LE || request_ttl_seconds
))
```

`session_nonce` é aleatório, criptograficamente seguro e novo a cada
solicitação. Após resolver a chave da pulseira, o servidor persiste a
unicidade de `(band_id, session_nonce)`. Repetições do mesmo advertising são
sightings da interação original e nunca renovam sua expiração, calculada a
partir do primeiro sighting autenticado.

O contador monotônico permanece apenas na decisão GATT. Ele deve ser
persistido antes do uso, em partição NVS dedicada, e validado por testes de
queda de energia. Não se assume vida útil teórica sem medição da partição e
do padrão real de gravação.

### Separação de domínio e confirmação vinculada ao desafio

Todos os CMACs recebem um byte de domínio implícito antes da mensagem:

| Domínio | Byte |
|---|---:|
| Advertising | `0x01` |
| Challenge | `0x02` |
| Decision | `0x03` |
| Result | `0x04` |
| Cancel | `0x05` |

O `band_auth_tag` é calculado sobre a transcrição canônica completa, mesmo
que a mensagem `Decision` não repita todos os campos no fio:

```text
0x03 || protocol_version || transaction_id || challenge_nonce ||
interaction_id || attraction_id || operator_gateway_id || amount ||
decision || transaction_counter
```

Assim, a confirmação prova exatamente a transação, atração e custo mostrados.
Challenge, Result e Cancel seguem a mesma regra de separação de domínio.

### Reserva antes do acionamento; débito depois da entrega

Após confirmação e validação de saldo/regras, o servidor cria uma
`credit_reservation` atômica e exclusiva por `transaction_id`. A reserva
reduz o saldo disponível, mas não cria `ledger_entry` e não é um débito.

O fluxo passa a ser:

```text
confirmed_pending_validation
  -> credit_reserved
  -> actuation_pending
  -> completed
```

Cada acionamento possui `actuation_command_id` único. O gateway persiste o
comando e o resultado; retries do mesmo ID retornam o resultado já conhecido
e nunca acionam novamente a atração.

Somente um ack positivo e autenticado converte, na mesma transação
PostgreSQL, a reserva em `ledger_entry` de débito e a interação em
`completed`. Um ack autenticado `not_executed` permite nova tentativa
controlada ou liberação da reserva. Timeout, perda de ack ou resultado contraditório levam a
`reconciliation_required`; a reserva permanece e nenhum segundo comando é
emitido automaticamente.

### Exceções exigem identidade humana

Override, liberação manual de reserva, ajuste e resolução de reconciliação
exigem `operator_id`, além de `operator_gateway_id`, motivo e horário. O
gateway identifica o terminal; não substitui a identidade da pessoa que
tomou a decisão excepcional.

### Cancelamento e UX da pulseira

Cancelamento livre é aceito somente antes do despacho do comando físico. Uma
vez em `actuation_pending`, o servidor não sabe se a atração já foi liberada:
só um ack `not_executed` ou uma reconciliação identificada pode liberar a
reserva. Depois do commit do ledger, correções financeiras usam ajuste
auditado. Quando o cancelamento for confirmado, o servidor envia `Cancel`
autenticado se houver conexão GATT.

Após o clique, a pulseira mostra progresso por no máximo 30 segundos. Sem
resultado terminal, muda para `attention_required` e exibe “PROCURE OPERADOR”,
mantendo `transaction_id` e o advertising da mesma solicitação para permitir
reconexão e entrega tardia de Result/Cancel. Esse estado não cria uma nova
interação nem autoriza novo consumo.

### Colisão do código visual

Solicitações ativas com o mesmo `display_code` são publicadas como ambíguas e
nenhuma pode ser reivindicada. O TFT orienta o operador a pedir que uma das
pessoas gere novo código. A segunda solicitação nunca fica invisível e a
resolução jamais usa RSSI ou posição na fila.

## Consequências

- ADRs 0003/0004 permanecem como histórico, mas os pontos acima deixam de ser
  vigentes.
- O modelo PostgreSQL precisa incluir reservas, comandos idempotentes e
  reconciliação antes das migrations da Etapa 4.
- O gateway precisa de store-and-forward do comando e do ack de acionamento.
- Os vetores criptográficos devem cobrir adulteração de atração, custo,
  `challenge_nonce` e domínio de mensagem.
- Antes do hardware de produção, um protótipo deve provar onde `band_key`
  reside e como o ESP32 executa CMAC sem expor o segredo; aceleração AES, por
  si só, não comprova integração com chave não exportável em eFuse.
- “Validação exaustiva” passa a significar revisão manual de consistência;
  garantias formais dependerão de testes de propriedades e concorrência.
