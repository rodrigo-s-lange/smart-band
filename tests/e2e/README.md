# Testes ponta a ponta

Cenários obrigatórios:

- solicitação, seleção, confirmação e débito aprovado
- timeout de confirmação (sem clique) sem débito
- anúncio recebido por vários gateways e uma única entrada
- duas pulseiras e dois brinquedos simultâneos
- dois operadores selecionando o mesmo código
- código visual duplicado
- gateway operador diferente do gateway de rádio
- perda do gateway de rádio e fallback
- replay de advertising, desafio e confirmação
- repetição do mesmo `transaction_id`
- saldo insuficiente
- reserva criada sem lançamento de ledger
- ack positivo consome reserva e cria exatamente um débito
- repetição do mesmo `actuation_command_id` não aciona nem debita novamente
- ack `not_executed` não cria débito
- ack perdido leva a reconciliação sem auto-retry físico
- override e liberação de reserva exigem gateway cadastrado e motivo
- cancelamento do operador em qualquer estágio, incluindo durante
  confirmação (cancelamento sempre vence a corrida, ADR 0003)
- cancelamento libera reserva antes do despacho; durante acionamento exige
  `not_executed` ou reconciliação
- esgotamento das 3 tentativas de retry do lease sem gateway de rádio disponível
- dois `display_code` colidentes ficam visíveis como ambíguos e não aceitam claim
- replay do mesmo `session_nonce` não renova a expiração
- adulteração de custo, atração, nonce ou domínio invalida `band_auth_tag`
- 30s sem resultado move a pulseira para `attention_required`
- reinício da appliance e recuperação da fila/ledger
- operação integral sem internet
