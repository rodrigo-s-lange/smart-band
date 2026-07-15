# Camadas e responsabilidades

## Pulseira

Responsavel por identidade fisica, interface do participante, contador do
protocolo e exibicao de estado. Pode manter uma copia visual do saldo, mas nao
e a autoridade financeira ou transacional.

## Gateway

Terminal de uma atracao. Conduz a comunicacao de proximidade, identifica a
atracao, solicita a transacao ao edge e apresenta o resultado. Nao debita saldo
isoladamente.

## Edge local

Autoridade durante o evento. Mantem ledger, saldo, associacoes, regras,
auditoria e outbox. Deve operar sem internet e falhar de forma segura quando a
autoridade local estiver indisponivel.

## Sincronizacao

Publica a outbox para a cloud com retry e confirmacao. A entrega e pelo menos
uma vez, portanto o consumidor cloud deve ser idempotente.

## Cloud EasySmart

Consolida instalacoes, eventos e transacoes, fornece operacao remota e
observabilidade. Usa infraestrutura compartilhada da EasySmart Platform com
database, topicos, ACLs, segredos e dashboards isolados para `smartband`.

## Frontend

Opera participantes, sessoes, pulseiras, creditos, atracoes e gateways. A parte
local deve continuar disponivel sem internet.

## Contratos

OpenAPI, schemas de eventos e protocolo logico de proximidade sao fronteiras
versionadas. Implementacoes nao devem depender de estruturas internas de outra
camada.

## Deploy

O i5 e laboratorio. O deploy edge deve funcionar em outro host Linux a partir
do repositorio e da configuracao externa do ambiente.
