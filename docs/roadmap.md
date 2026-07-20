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

## Trilha paralela D — demonstração comercial

Uma simulação em Streamlit pode avançar por D0–D7 para apoiar a reunião com a
VRPlay, sem alterar o estado das Etapas 5–7. Ela usa dados fictícios, cockpit de
pulseira/gateway/appliance e cenários determinísticos. O alvo externo é
`https://pulseira.easysmart.com.br` por HTTPS autenticado, com fallback LAN.

Estado em 2026-07-19: D0–D6 concluídas e D7 parcialmente concluída.

A trilha, seus limites e gates estão em
[commercial-simulation-plan.md](demo/commercial-simulation-plan.md) e
[demo-commercial-simulation.md](stage-gates/demo-commercial-simulation.md).
Fixtures não resolvem decisões comerciais nem autorizam hardware, firmware ou
frontend definitivo.

Timeout, lease e até três tentativas de rádio pela porta opaca definida na
ADR 0012 estão materializados com persistência, fencing, retomada por banco e
simulador fail-closed.
Ela não congela o Challenge/Decision final. Cadastro, pagamentos, validade,
preço, duração e acionamento aguardam as decisões do cliente listadas em
[client-decisions-pending.md](product/client-decisions-pending.md). O handoff e
os critérios de aceite estão em [CURRENT_STATE.md](../CURRENT_STATE.md).

Nenhuma fatia posterior dependente dessas decisões fica autorizada por esta
entrega; o próximo escopo técnico deve ser registrado no handoff canônico.

A ADR 0015 ratifica o encerramento obrigatório no gateway e a métrica de uso por
atração. Modelo, API, eventos e migrations desse ciclo operacional ainda não
estão implementados e devem entrar em uma fatia explicitamente autorizada.
