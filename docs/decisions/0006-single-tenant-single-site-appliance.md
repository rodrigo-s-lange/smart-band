# ADR 0006 — Appliance single-tenant e single-site

Status: accepted — 2026-07-18

## Contexto

O primeiro caso real é a VRPlay: uma operação de realidade virtual em um
shopping, ocupando aproximadamente 1.500 m², com uma appliance local, 7 a 10
gateways, 25 a 40 pulseiras e várias atrações.

`Evento` não significa necessariamente uma feira temporária. No Smart-Band ele
é o contexto operacional que define período, atrações, preços e regras. Uma
unidade permanente pode manter um evento longo, como “Operação regular”, e
eventos posteriores preservam o histórico sem trocar de site.

## Decisão

Cada appliance atende exatamente um cliente (`tenant`) e um único site
operacional por vez.

- a appliance possui uma configuração singleton com `tenant_id` e `site_id`
- o site ativo precisa pertencer ao tenant configurado
- um site pode manter múltiplos eventos históricos
- existe no máximo um evento ativo por site
- gateways, atrações, operadores, pulseiras e transações são sempre
  vinculados ao escopo local
- uma segunda unidade simultânea, ainda que do mesmo cliente, usa outra
  appliance e outro banco operacional
- consolidação externa entre unidades poderá ser adicionada depois, sem entrar
  no caminho crítico de autorização

No caso inicial:

```text
VRPlay (tenant)
└── unidade no shopping (site)
    └── operação regular ou campanha vigente (event)
        ├── 1 appliance
        ├── 7–10 gateways
        ├── 25–40 pulseiras
        └── atrações de realidade virtual
```

Gateway e atração permanecem entidades distintas. Uma transação registra
separadamente o gateway onde o operador selecionou o código, o gateway usado
como ponte BLE, a atração e o comando físico.

## Consequências

- isolamento, backup, restore e suporte ficam limitados a uma unidade
- não existe risco de misturar clientes no banco operacional local
- relatórios históricos podem atravessar eventos do mesmo site
- movimentar uma appliance para outro site exige procedimento operacional
  explícito; não é uma troca durante a operação
- uma appliance não consolida operações simultâneas de vários sites
- o modelo PostgreSQL deve impedir mais de uma configuração de appliance e
  mais de um evento ativo no mesmo site
