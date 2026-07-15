# End-to-end tests

Cenarios obrigatorios:

- debito aprovado e negado
- repeticao do mesmo `transaction_id`
- concorrencia de gateways sobre a mesma pulseira
- cloud offline e retorno da sincronizacao
- replay e mensagens fora de ordem
- backup, restore e reprocessamento da outbox
- carga superior ao alvo inicial de 25 pulseiras
