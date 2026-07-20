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
- Toda pulseira vinculada ao uso permanece ocupada e não pode iniciar outra
  atividade enquanto esse uso estiver aberto.
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

## Contingência ainda aberta

Se o gateway estiver indisponível, não haverá liberação automática. A VRPlay
deve decidir se um gateway substituto ou uma ação administrativa auditada pode
fechar o uso, quais permissões exige e como comprovar o término real. Essa
exceção permanece no gate D7/D8 do cliente.

## Consequências

O modelo definitivo precisará de um registro de uso separado da transação, uma
restrição de no máximo um uso aberto por pulseira, fechamento idempotente e
métricas por atração. OpenAPI, eventos, migrations e consumidores ainda devem
ser versionados antes da implementação no produto; esta ADR não declara essa
persistência como já entregue.
