# Edge Sync

Transporta eventos duraveis do edge para a cloud.

Responsabilidades:

- ler a outbox local
- publicar por MQTT over WSS com identidade do edge
- repetir com backoff ate confirmacao
- preservar ordem quando exigida pelo contrato
- marcar confirmacao sem perder eventos
- reconciliar divergencias de forma observavel

Nao contem regra de saldo e nao reescreve o ledger local.
