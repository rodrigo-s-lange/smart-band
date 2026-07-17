# Fluxo transacional

1. Pessoa mantém o botão pressionado.
2. Pulseira cria solicitação efêmera autenticada e mostra o código.
3. Gateways reportam sightings ao servidor.
4. Servidor autentica, deduplica e publica a fila global.
5. Pessoa verbaliza o código no brinquedo desejado.
6. Operador seleciona o código no TFT.
7. Servidor faz claim atômico e cria `transaction_id`.
8. Servidor escolhe gateway de rádio e envia desafio GATT.
9. Pulseira mostra atração e custo.
10. Pessoa confirma por clique curto.
11. Pulseira autentica a decisão.
12. Servidor valida saldo e regras.
13. Ledger e saldo mudam na mesma transação PostgreSQL.
14. Gateway operador recebe autorização de acionamento.
15. Pulseira e gateway recebem o resultado.

## Invariantes

- código verbalizado não autoriza débito sozinho
- confirmação é vinculada à atração, custo e transação
- um `transaction_id` causa no máximo um débito
- timeout ou rejeição não alteram saldo
- gateway e pulseira não são autoridades do saldo
- internet não participa do fluxo
- falha de acionamento é auditada separadamente do débito
