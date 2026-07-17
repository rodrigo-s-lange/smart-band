# OpenAPI e canais em tempo real

Contratos previstos:

- administração de participantes, sessões, pulseiras e créditos
- atrações, gateways e operadores
- ingestão de sightings autenticados
- claim e cancelamento de solicitações
- ledger, estorno e auditoria
- health, backup e restore

Atualizações da fila poderão usar WebSocket ou outro canal local. A escolha de
transporte ainda está aberta, mas payloads e estados devem ser versionados.
