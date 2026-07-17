# Gateway Coordinator

Fronteira lógica responsável por coordenar gateways sem assumir regras de
saldo. Pode começar integrado à Edge API e ser extraído somente se necessário.

## Responsabilidades

- consolidar sightings por `interaction_id`
- manter presença recente dos gateways
- escolher `radio_gateway_id`
- executar claim lease e fallback de rádio
- transportar desafios e respostas GATT
- publicar atualizações da fila para TFTs

O `operator_gateway_id` define a atração; o `radio_gateway_id` é apenas a ponte
BLE escolhida para aquela sessão.
