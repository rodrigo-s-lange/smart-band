# Smart-Band — estado atual e handoff

Atualizado em 2026-07-19. Este é o ponto de entrada operacional para continuar
o projeto sem acesso ao histórico de conversas.

## Fontes e baseline

- Repositório oficial: `rodrigo-s-lange/smart-band`.
- Baseline funcional mais recente: **PR 10**, merge
  `b02d73f6b66c3010187101c416407a43fcdfe990`.
- `main` oficial atual após a demonstração comercial: **PR 14**, merge
  `ed230abfd5e770b459ab545e06f557548a940d96`.
- Vault baseline documental desta sincronização:
  `405f2616c6a8e831a68e8e7ff2d06ac003e4bd55`.
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
- plano D0–D7 e ADR da demonstração comercial em Streamlit;
- demonstração comercial isolada em `apps/demo-streamlit`, com SQLite
  compartilhado, fixture determinística, cockpit virtual e seis áreas;
- fluxo completo simulado de cadastro, carga, solicitação, confirmação,
  acionamento e débito exatamente uma vez;
- cenários simulados de fallback de rádio, `not_executed`, resultado ambíguo e
  tamper, sem alterar contratos ou regras definitivas do produto;
- container, healthcheck, autenticação por senha e compose isolado em
  `deploy/demo`.
- OLED azul 128×32 e TFT 170×320 vertical reproduzidos com mensagens curtas,
  fonte grande e sem avisos repetitivos de simulação;
- clique simples/duplo, TTL de 30 segundos, rotação de código, confirmação em
  30 segundos, sessão de 5 minutos e encerramento explícito;
- término sem débito ou estorno automático e atração bloqueada até o `OK` do
  gateway.

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
- vibracall e padrões finais de acessibilidade;
- sensor de remoção, resposta a alertas e extensão BLE v2;
- gamificação/sorteios, métricas BLE de ocupação e comissão de vendas;
- publicação permanente do produto e seu SLA continuam bloqueados; o acesso
  temporário da demo em `https://pulseira.easysmart.com.br` segue a trilha D6.

Operações OpenAPI marcadas `client-decision-blocked` continuam representativas e
não autorizam implementação definitiva.

## Próximo marco autorizado

O próximo marco é de **decisão com a VRPlay**, não de implementação funcional.

Usar a folha executiva do vault para obter:

- D1–D8 respondidas ou com regra provisória explicitamente aprovada;
- D9–D12 com responsável e prazo antes da operação assistida;
- D13–D18 decididas antes do hardware, da demo ou do módulo opcional afetado;
- nome de quem aprovou, data, exceções e evidência necessária;
- tabela inicial das atrações e seus métodos de liberação/ack.

Não há nova fatia funcional autorizada neste momento. Challenge/Decision final,
cadastro, pagamentos, atração, frontend, acionamento, hardware e firmware não
podem avançar até que as respostas aplicáveis virem ADR, contrato e critérios de
aceite.

A ADR 0013 e o contrato `contracts/proximity/tamper-status.md` são propostas de
fronteira para a reunião. O advertising v1 continua vigente; não existem sensor,
alerta contínuo, dashboard público ou firmware autorizados por esses documentos.

## Trilha paralela de demonstração

A [ADR 0014](docs/decisions/0014-streamlit-commercial-simulation.md) aceita
Streamlit exclusivamente para a simulação. Escopo, cenários, D0–D7, gates e
roteiro estão em
[commercial-simulation-plan.md](docs/demo/commercial-simulation-plan.md).

Status: **D0–D6 concluídas; D7 pendente**. A demo está ativa temporariamente em
`https://pulseira.easysmart.com.br`, para a reunião de terça-feira com público
comercial, operacional e técnico. A autenticação usa senha temporária externa ao
Git. A demo não autoriza nem conclui backend, frontend operacional, contratos
comerciais, hardware ou firmware.

Evidência local da demo em 2026-07-19:

- 10 testes automatizados aprovados, incluindo três consumidores do mesmo banco,
  três resets completos e idempotência financeira;
- smoke de todas as páginas com `streamlit.testing.v1.AppTest`;
- fluxo S1 executado em Chrome headless do cadastro ao estado `LIBERADO`, com
  saldo reduzido de 5 para 4;
- healthcheck local do Streamlit aprovado.
- fluxo visual validado em Chrome nos estados código, confirmação, liberação e
  cronômetro;
- timeouts, rotação, bloqueio durante sessão, encerramento antecipado e
  confirmação do gateway cobertos por testes.

Evidência de publicação:

- PR 14 integrada em `ed230abfd5e770b459ab545e06f557548a940d96`, com
  `Commercial Demo` e `Contracts` verdes;
- imagem Docker construída no i5 e container saudável;
- serviço ligado somente a `127.0.0.1:8501`;
- Cloudflare Tunnel exclusivo, HTTPS e senha temporária;
- senha inválida recusada e S1 completo executado pelo domínio público;
- fallback LAN testado e bind interno restaurado;
- fixture restaurada após a validação.

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
