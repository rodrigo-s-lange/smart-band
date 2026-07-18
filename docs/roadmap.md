# Roadmap

Estado em 2026-07-18: etapas 1–4 concluídas e protegidas pelos gates
[03](stage-gates/03-executable-contracts.md) e
[04](stage-gates/04-postgresql-model.md). A fundação da Etapa 5 está em
execução no [gate parcial 05](stage-gates/05-backend-foundation.md). A ingestão
BLE autenticada, a deduplicação e o SSE já estão materializados; claim e o fluxo
transacional continuam em execução. O claim CAS, a escolha determinística do
gateway de rádio e a criação atômica do transaction intent já estão
materializados. A identidade operacional é o gateway cadastrado, sem login
individual de quem o utiliza (ADR 0010). A correção de invariantes da PR 7 está
integrada e o gate atual de decisões do cliente é definido pela ADR 0011.

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

A próxima fatia autorizada da Etapa 5 implementa timeout, lease e até três
tentativas de rádio pela porta opaca definida na ADR 0012, com persistência,
fencing, retomada por banco e simuladores.
Ela não congela o Challenge/Decision final. Cadastro, pagamentos, validade,
preço, duração e acionamento aguardam as decisões do cliente listadas em
[client-decisions-pending.md](product/client-decisions-pending.md). O handoff e
os critérios de aceite estão em [CURRENT_STATE.md](../CURRENT_STATE.md).
