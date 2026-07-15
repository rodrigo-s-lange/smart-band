# Fluxo de transacao

1. O gateway inicia uma sessao de proximidade e envia um desafio.
2. A pulseira responde com identidade, contador e prova de sessao.
3. O gateway cria um `transaction_id` unico e solicita a operacao ao edge.
4. O edge valida identidades, associacao, atracao, saldo, regras e idempotencia.
5. Ledger e saldo sao atualizados atomicamente no PostgreSQL local.
6. O edge devolve o mesmo resultado para repeticoes do `transaction_id`.
7. O gateway confirma a operacao e atualiza a pulseira.
8. A outbox registra o evento de sincronizacao na mesma unidade de consistencia.
9. O servico de sync envia o evento para a cloud quando houver conectividade.
10. A cloud consome de forma idempotente e confirma o recebimento.

## Invariantes

- um `transaction_id` causa no maximo um debito
- cloud offline nao bloqueia a operacao local
- pulseira e gateway nao sao autoridades do saldo
- telemetria tecnica nao se mistura ao ledger de negocio
- toda transacao identifica tenant, site, evento, sessao, pulseira, gateway e atracao
- ordem transacional usa sequencia local, nao apenas relogio de parede
