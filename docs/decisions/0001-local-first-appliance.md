# ADR 0001 — Appliance local-first

Status: accepted — 2026-07-17

## Decisão

O Smart-Band opera integralmente em uma appliance Linux local com SSD,
PostgreSQL, backend e frontend. Internet e EasySmart Platform não são
dependências operacionais.

Serviços externos podem fornecer licença, atualização, suporte, monitoramento
técnico e backup autorizado, sem entrar no caminho de autorização.

## Consequências

- baixa latência e continuidade offline
- dados pessoais locais por padrão
- necessidade de backup, restore, UPS e atualização reproduzível
- appliance comercial independente do laboratório i5
