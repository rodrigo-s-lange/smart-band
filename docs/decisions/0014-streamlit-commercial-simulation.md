# ADR 0014 — Streamlit para a simulação comercial

- Status: aceita
- Data: 2026-07-19

## Contexto

O projeto precisa de uma demonstração navegável para reunião comercial antes do
hardware e de várias decisões da VRPlay. Implementar imediatamente o frontend
definitivo acoplaria a apresentação a regras ainda abertas.

## Decisão

- usar Streamlit exclusivamente na demonstração comercial;
- preservar `apps/operator-web` como frontend operacional definitivo;
- hospedar a demo no i5 com deploy reproduzível e fallback LAN;
- usar `https://pulseira.easysmart.com.br` como URL pública pretendida;
- publicar somente por proxy/túnel HTTPS autenticado;
- não expor banco, Edge API ou portas do i5 diretamente;
- usar dados fictícios, cenários determinísticos e marca de simulação;
- manter estado compartilhado fora da sessão individual do navegador;
- integrar a Edge API apenas nas capacidades já vigentes;
- impedir que fixtures sejam tratadas como decisões ou seeds de produção.

## Consequências

A demo avança por uma trilha D0–D7 independente. Ela não conclui as Etapas 5–7,
não autoriza contratos bloqueados e não substitui testes do produto. Streamlit e
seu estado de cenário não entram no domínio ou ledger. DNS, credenciais e acesso
externo dependem de autorização operacional específica.

Plano: [commercial-simulation-plan.md](../demo/commercial-simulation-plan.md).
