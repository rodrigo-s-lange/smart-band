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
13. Servidor cria uma reserva atômica de crédito; ainda não há débito.
14. Servidor persiste um `actuation_command_id` e o envia ao gateway operador.
15. Gateway executa cada comando no máximo uma vez e persiste o ack.
16. Ack positivo converte reserva em débito na mesma transação PostgreSQL.
17. Pulseira e gateway recebem o resultado autenticado.
18. O ack positivo também abre um uso operacional e mantém a pulseira ocupada.
19. Ao terminar, com ou sem cronômetro, o gateway responsável solicita o
    fechamento explícito do uso.
20. A appliance fecha o uso de forma idempotente, calcula a duração e libera as
    pulseiras vinculadas para novas atividades.

## Invariantes

- código verbalizado não autoriza débito sozinho
- confirmação é vinculada à atração, custo e transação
- um `transaction_id` causa no máximo um débito
- um `actuation_command_id` causa no máximo um acionamento físico
- débito só existe depois de ack positivo do acionamento
- ack `not_executed` libera ou mantém uma reserva conforme decisão auditada; ack
  ambíguo exige reconciliação e nunca dispara novo acionamento automático
- timeout ou rejeição não alteram saldo
- gateway e pulseira não são autoridades do saldo
- internet não participa do fluxo
- override e reconciliação exigem gateway cadastrado, ação, motivo e horário
- transação financeira concluída não significa uso operacional encerrado
- `00:00` e solicitação da pulseira apenas pedem atenção; somente o fechamento
  no gateway libera a pulseira
- duração de uso é medida do ack positivo até o fechamento aceito pela appliance
