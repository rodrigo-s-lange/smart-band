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
- falha de acionamento após autorização
- override manual do operador após falha de acionamento (sem novo débito)
- cancelamento do operador em qualquer estágio, incluindo durante
  confirmação (cancelamento sempre vence a corrida, ADR 0003)
- cancelamento chegando depois do commit do ledger (deve ser rejeitado como no-op)
- esgotamento das 3 tentativas de retry do lease sem gateway de rádio disponível
- retenção da publicação de um segundo `display_code` colidente até o primeiro resolver
- reinício da appliance e recuperação da fila/ledger
- operação integral sem internet
