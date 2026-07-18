# Roadmap

Estado em 2026-07-18: etapas 1–4 concluídas e protegidas pelos gates
[03](stage-gates/03-executable-contracts.md) e
[04](stage-gates/04-postgresql-model.md). A fundação da Etapa 5 está em
execução no [gate parcial 05](stage-gates/05-backend-foundation.md). A ingestão
BLE autenticada, a deduplicação e o SSE já estão materializados; claim e o fluxo
transacional continuam em execução. O claim CAS, a escolha determinística do
gateway de rádio e a criação atômica do transaction intent já estão
materializados.

1. Domínio e invariantes
2. Contrato BLE e máquina de estados
3. Fila global e coordenação de gateways
4. Modelo PostgreSQL e migrations
5. Backend local
6. Simuladores de pulseira, gateway e TFT
7. Frontend operacional e modo kiosk
8. Segurança, concorrência, backup e restore
9. Appliance piloto
10. Hardware e firmware do gateway
11. Hardware e firmware da pulseira
12. Piloto operacional

Hardware começa somente depois de confirmação, idempotência, concorrência,
replay e recuperação estarem validados com simuladores.

A próxima fatia da Etapa 5 despacha o Challenge GATT pelo gateway de rádio,
valida a Decision da pulseira e trata timeout/retry do lease, sem iniciar
hardware ou firmware.
