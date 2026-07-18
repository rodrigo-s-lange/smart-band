# Gate da Etapa 3 — contratos executáveis

Status: concluída — 2026-07-18

## Escopo entregue

- wire format BLE versionado para Advertising, Challenge, Decision, Result e Cancel
- vetores AES-128-CMAC estruturados e recalculáveis
- JSON Schema 2020-12 com exemplos válidos e inválidos
- OpenAPI 3.1 para Edge API, fila SSE e fluxo transacional
- modelo de domínio e invariantes alinhados à ADR 0005
- validação local e CI usando o mesmo comando

## Comando de aceite

```bash
python -m pip install -r tools/validation/requirements.txt
python tools/validation/validate.py
```

O workflow `.github/workflows/contracts.yml` executa esse gate em toda pull
request e em pushes para `main`.

## Propriedades verificadas

- exemplos válidos de eventos passam e inválidos são rejeitados
- reserva de crédito não aceita `ledger_entry_id`
- override sem gateway cadastrado, ação ou motivo é rejeitado
- estados de reserva, acionamento e reconciliação existem no OpenAPI
- resultados físicos são `succeeded`, `not_executed` ou `ambiguous`
- cinco tipos BLE usam bytes de domínio distintos
- tamanhos dos payloads no fio permanecem congelados
- adulterar o custo muda a tag da Decision
- links Markdown locais apontam para arquivos existentes

## Fora deste gate

O gate não prova constraints PostgreSQL, concorrência, recuperação após queda
ou comportamento do gateway. Essas garantias pertencem às Etapas 4–6. A
Etapa 4 só começa depois de decisão explícita sobre modelo, ferramentas de
migration e estratégia de testes de banco.
