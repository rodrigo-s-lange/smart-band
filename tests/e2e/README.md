# Testes ponta a ponta

Cenários obrigatórios:

- solicitação, seleção, confirmação e débito aprovado
- rejeição e timeout sem débito
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
- reinício da appliance e recuperação da fila/ledger
- operação integral sem internet
