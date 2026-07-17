# Edge API

Aplicação principal da appliance local e autoridade transacional.

## Responsabilidades

- participantes, sessões e associação de pulseiras
- gateways, atrações e operadores
- ingestão autenticada de sightings
- fila global, claims e transaction intents
- desafio e validação da confirmação da pulseira
- ledger, saldo, carga, débito, estorno e ajuste
- auditoria, health checks, backup e restore

## Restrições

- não depende de internet para operar
- não confia em saldo informado por pulseira ou gateway
- não expõe banco diretamente à LAN
- não mistura telemetria técnica com ledger
