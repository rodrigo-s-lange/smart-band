# Smart-Band — estado atual e handoff

Atualizado em 2026-07-18. Este é o ponto de entrada operacional para continuar
o projeto sem acesso ao histórico de conversas.

## Fontes e baseline

- Repositório oficial: `rodrigo-s-lange/smart-band`.
- Baseline funcional mais recente: **PR 10**, merge
  `b02d73f6b66c3010187101c416407a43fcdfe990`.
- Vault baseline documental desta sincronização:
  `554ef34d4792710ae1960e79d2f2b1021dee8aa1`.
- Questionário canônico do cliente no vault:
  `C:\Users\Familia\vault\01-projetos\smart-band\processo-geral-e-decisoes-do-cliente.md`.
- Laboratório reproduzível:
  `/home/rodrigo/projects/products/smart-band` no i5 `192.168.0.121`.
- Migrations vigentes: **11**, de `00001` a `00011`.

O hash do vault acima identifica a baseline lida para esta sincronização, não
promete que ela continuará sendo o HEAD. Sempre verificar o estado real com
`git rev-parse HEAD` e `git status`. Isso evita uma referência circular quando o
vault registra posteriormente a integração de uma PR do código.

Da mesma forma, o HEAD do Git pode avançar por correções documentais sem mudar a
baseline funcional. Verificar `git rev-parse HEAD` antes de trabalhar.

## Estado das etapas

- Etapas 1 a 4: concluídas.
- Etapa 5 — backend local: em execução.
- Etapas 6 a 9: ainda não concluídas.
- Etapas 10 e 11 — hardware e firmware: bloqueadas pelo roadmap.
- Etapa 12 — piloto operacional: futura.

## Entregas integradas

- appliance local-first, single-tenant e single-site;
- modelo PostgreSQL, ledger append-only, reservas e comandos idempotentes;
- advertising BLE autenticado, resolução da pulseira e código Crockford;
- sightings deduplicados, fila global e SSE retomável;
- gateway cadastrado como identidade operacional, sem login humano no fluxo;
- claim CAS e escolha determinística do gateway de rádio;
- criação atômica de claim, transaction intent e outbox;
- proteção de uma única interação ativa por pulseira, inclusive em
  `actuation_failed` e `reconciliation_required`;
- motor persistido de retry de rádio com payload opaco;
- `dispatch_id`, nonce, tentativa e lease usados como fencing;
- `waiting_for_radio`, seleção/reuso de gateway e proibição de sighting stale;
- worker recuperável pelo PostgreSQL, com I/O fora da transação;
- esgotamento atômico após três falhas, sem reserva ou lançamento de ledger;
- transporte simulado fail-closed e eventos técnicos versionados.

## Evidência da PR 10

- merge: `b02d73f6b66c3010187101c416407a43fcdfe990`;
- 11 migrations aplicadas e revertidas em PostgreSQL real;
- `sqlc` 1.31.1 regenerado sem divergência;
- `go test -race ./...`, `go vet ./...` e build do `edge-api` aprovados;
- imagem do backend construída;
- workflows [Contracts](https://github.com/rodrigo-s-lange/smart-band/actions/runs/29669072949),
  [Database](https://github.com/rodrigo-s-lange/smart-band/actions/runs/29669072940)
  e [Backend](https://github.com/rodrigo-s-lange/smart-band/actions/runs/29669072936)
  concluídos com sucesso.

## Gate atual de produto

Status: **aguardando validação do cliente**.

As decisões estão resumidas em
[docs/product/client-decisions-pending.md](docs/product/client-decisions-pending.md)
e detalhadas no questionário do vault. Não podem ser resolvidas por suposição,
fixture, preferência técnica ou inferência de uma LLM.

Permanecem bloqueados:

- cadastro, dados pessoais, menores e LGPD;
- venda, confirmação, cancelamento e conciliação de pagamentos;
- significado, pacotes, validade, devolução e transferência de créditos;
- preço, unidades e duração das atrações;
- conteúdo final mostrado e autenticado pela pulseira;
- início, término e contingência do tempo adquirido;
- método físico de liberação e critério de ack de cada atração;
- perfis administrativos, cortesias, ajustes e reconciliação;
- regras entre campanhas, eventos e unidades;
- relatórios comerciais, fechamento e continuidade operacional;
- contratos administrativos definitivos de gateway e atração.

Operações OpenAPI marcadas `client-decision-blocked` continuam representativas e
não autorizam implementação definitiva.

## Próximo marco autorizado

O próximo marco é de **decisão com a VRPlay**, não de implementação funcional.

Usar a folha executiva do vault para obter:

- D1–D8 respondidas ou com regra provisória explicitamente aprovada;
- D9–D12 com responsável e prazo antes da operação assistida;
- nome de quem aprovou, data, exceções e evidência necessária;
- tabela inicial das atrações e seus métodos de liberação/ack.

Não há nova fatia funcional autorizada neste momento. Challenge/Decision final,
cadastro, pagamentos, atração, frontend, acionamento, hardware e firmware não
podem avançar até que as respostas aplicáveis virem ADR, contrato e critérios de
aceite.

## Trabalho seguro enquanto o cliente decide

Sem novo escopo formal, são permitidos apenas:

- correções de defeito ou segurança que preservem as decisões vigentes;
- manutenção de CI, testes, documentação e ambiente reproduzível;
- diagnóstico operacional sem alterar regra de negócio;
- preparação da reunião, inventário das atrações e coleta de documentação dos
  equipamentos;
- protótipos descartáveis claramente isolados, sem virar contrato ou produção.

Qualquer nova funcionalidade exige atualização prévia deste arquivo e, quando
alterar fronteira ou invariante, uma ADR.

## Como desbloquear o desenvolvimento

Para cada resposta relevante:

1. registrar a decisão e o aprovador no vault;
2. confirmar a validação explícita da VRPlay;
3. criar ou atualizar ADR;
4. versionar OpenAPI, eventos, banco ou BLE afetados;
5. definir critérios de aceite e cenários de teste;
6. registrar aqui a próxima fatia autorizada;
7. somente então implementar consumidores.

## Validação do estado atual

```bash
python tools/validation/validate.py
python tools/database/validate.py --docker-container <postgres-temporario>
cd apps/edge-api
go test -race ./...
go vet ./...
go build ./cmd/edge-api
```

Se migrations ou queries forem alteradas, regenerar `sqlc` 1.31.1 e provar que
o resultado versionado não divergiu.

## Protocolo de atualização

Uma entrega só altera o estado deste arquivo depois de passar contratos, testes
e procedimentos relevantes. Na mesma entrega, atualizar:

- `CURRENT_STATE.md`;
- `AGENTS.md`, quando fronteiras, bloqueios ou comportamento mudarem;
- `README.md`, roadmap e gate da etapa;
- ADR e documentação correspondente no vault;
- contagem de migrations e evidência de CI, quando aplicável.

Não declarar trabalho concluído apenas porque compilou.
