# Roadmap

Estado em 2026-07-18: etapas 1–3 concluídas e protegidas pelo gate em
[docs/stage-gates/03-executable-contracts.md](stage-gates/03-executable-contracts.md).
A Etapa 4 aguarda decisão explícita antes da implementação.

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

A Etapa 4 deve materializar `credit_reservation`, `actuation_command` e
`operational_resolution`, além das constraints da ADR 0005. Nenhuma migration
de ledger pode preservar a antiga ordem “débito antes do acionamento”.
