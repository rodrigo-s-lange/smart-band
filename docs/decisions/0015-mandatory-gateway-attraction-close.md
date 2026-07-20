# ADR 0015 — Encerramento obrigatório da atração no gateway

- Status: aceita
- Data: 2026-07-19

## Contexto

O ack positivo de liberação conclui a transação financeira, mas não comprova que
o uso da atração terminou. Atividades temporizadas e não temporizadas precisam
da mesma fronteira operacional para impedir que a pulseira participe de duas
atrações e para produzir métricas comparáveis de permanência.

## Decisão

- Todo ack positivo de liberação abre um uso operacional da atração.
- Toda pulseira vinculada permanece ocupada até um fechamento normal ou de
  contingência. Uma nova atividade nunca cria duas participações ativas: ela
  fecha atomicamente a participação anterior antes de abrir a nova.
- O encerramento é sempre uma ação explícita no gateway responsável pela
  atração, independentemente de existir cronômetro.
- `00:00`, término físico presumido, solicitação da pulseira ou ausência de
  telemetria podem alertar o operador, mas não liberam a pulseira.
- O fechamento é autenticado pela credencial do gateway, idempotente e auditado
  com uso, atração, gateway, início, encerramento e horário do servidor.
- A appliance registra `started_at` no ack positivo de liberação e `closed_at`
  no fechamento aceito. A duração operacional é `closed_at - started_at`.
- Em atividade de grupo, o fechamento libera todas as pulseiras vinculadas ao
  mesmo uso.
- Fechar o uso não cria novo débito, renovação ou estorno automático.
- Somente depois do fechamento a pulseira fica disponível e o gateway pode
  apresentar a atração como `LIVRE`.

Qualquer pessoa autorizada pode executar a ação no gateway. A auditoria continua
identificando o equipamento, não o operador humano, conforme a ADR 0010.

## Contingência aceita

1. O gateway responsável executa o fechamento normal.
2. Se ele estiver indisponível, qualquer gateway autenticado e ativo do mesmo
   site pode abrir a lista de usos ativos, selecionar o uso/pulseiras corretos e
   fechá-lo explicitamente. A auditoria registra gateway de abertura, gateway de
   fechamento e motivo `source_gateway_unavailable`.
3. Como último recurso, o início confirmado de outra atividade fecha
   atomicamente a participação anterior da pulseira com
   `implicit_close_on_reentry`. O horário do novo uso aproxima o fim anterior.

Em atividades de grupo, o autoencerramento por reentrada fecha somente a
participação daquela pulseira. O uso das demais pessoas continua ativo até o
fechamento explícito em um gateway.

Relatórios distinguem duração exata, proveniente de fechamento no gateway, de
duração estimada, proveniente de reentrada. A indisponibilidade operacional não
pode bloquear permanentemente a experiência da pessoa.

## Consequências

O modelo definitivo precisará de um registro de uso separado da transação, no
máximo uma participação ativa por pulseira, fechamento idempotente e métricas
com qualidade exata/estimada. OpenAPI, eventos, migrations e consumidores devem
ser versionados antes da implementação no produto; esta ADR não declara essa
persistência como já entregue.
