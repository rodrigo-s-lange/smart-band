# Smart-Band — estado atual e handoff

Atualizado em 2026-07-18. Este é o ponto de entrada canônico para continuar a
implementação sem acesso ao histórico de conversas.

## Fontes e baseline

- GitHub `rodrigo-s-lange/smart-band`: código e artefatos executáveis.
- Baseline funcional mais recente: PR 7, merge
  `4019f7171bc8d8f91872831bba338c1d6a88b572`.
- Vault commit validado: `9c61b59416f3b8219322b97fc9f84838f826b543`.
- Handoff correspondente no vault:
  `C:\Users\Familia\vault\01-projetos\smart-band\estado-atual-e-handoff.md`.
- Laboratório reproduzível:
  `/home/rodrigo/projects/products/smart-band` no i5 `192.168.0.121`.
- Migrations vigentes: **10**, de `00001` a `00010`.

O commit atual do próprio checkout deve ser verificado com `git rev-parse HEAD`.
O hash funcional acima identifica a última mudança de comportamento anterior a
esta sincronização documental e não substitui a leitura do HEAD.

## Estado do projeto

- Etapas 1 a 4: concluídas.
- Etapa 5 — backend local: em execução.
- Etapas 6 a 9: ainda não concluídas.
- Hardware e firmware: etapas 10 e 11, bloqueados pelo gate do roadmap.
- Piloto operacional: etapa 12.

Entregue e validado:

- appliance local-first, single-tenant e single-site;
- modelo PostgreSQL, ledger, reservas, comandos idempotentes e rollback;
- advertising BLE autenticado, resolução de pulseira e código Crockford;
- sightings deduplicados, fila global e SSE retomável;
- claim CAS e escolha determinística do gateway de rádio;
- gateway cadastrado como identidade operacional, sem login humano no fluxo;
- claim, transaction intent e outbox atômicos;
- bloqueio de nova interação em `actuation_failed`;
- retry de rádio definido sobre o mesmo claim e `transaction_id`;
- Contracts, Database e Backend verdes na PR 7.

## Gate atual de decisões do cliente

As decisões resumidas em
[docs/product/client-decisions-pending.md](docs/product/client-decisions-pending.md)
aguardam validação do cliente. Não podem ser resolvidas por suposição, fixture,
preferência técnica ou inferência de uma LLM.

Permanecem bloqueados:

- dados definitivos de cadastro, LGPD e tratamento de menores;
- venda, confirmação, cancelamento e conciliação de pagamentos;
- significado, pacotes, validade, devolução e transferência de créditos;
- preço, unidades e duração das atrações;
- conteúdo final mostrado e autenticado pela pulseira;
- método físico de liberação e critério de ack de cada atração;
- perfis administrativos, cortesias e ajustes financeiros;
- regras entre campanhas, eventos e unidades;
- relatórios comerciais e fechamento de caixa;
- contratos administrativos definitivos de gateway e atração.

## Próxima entrega autorizada

### Próxima fatia da Etapa 5 — motor de retry de rádio e transporte simulado

Objetivo: implementar a orquestração anterior à entrega do Challenge sem
congelar campos comerciais do payload GATT.

Escopo:

1. implementar a porta versionada em
   `contracts/gateway/radio-dispatch.md`, que aceita payload opaco;
2. despachar pelo `radio_gateway_id` vigente;
3. em falha ou timeout anterior à entrega, manter claim, `transaction_id`,
   atração e gateway de liberação;
4. incrementar `attempt_count`;
5. selecionar o rádio pela ADR 0012, preferindo candidato elegível ainda não
   tentado e reutilizando o melhor somente se necessário;
6. gerar novo `dispatch_id`, novo `challenge_nonce` e renovar o lease;
7. limitar a três tentativas e então expirar;
8. rejeitar resultado atrasado de nonce anterior;
9. publicar eventos e logs correlacionados;
10. persistir tentativas e retomá-las com worker orientado pelo PostgreSQL;
11. testar com transporte e gateways simulados, sem ESP32.

`delivered` significa confirmação técnica da escrita completa na pulseira, não
enfileiramento, recebimento pelo gateway, conexão GATT ou início da escrita.
Depois da terceira falha, interação e claim terminam `expired`, a transação
termina `cancelled` e a outbox informa `radio_attempts_exhausted`. A semântica
completa está na ADR 0012.

Arquivos candidatos — confirmar o desenho existente antes de editar:

- `apps/edge-api/internal/application/`;
- `apps/edge-api/internal/postgres/`;
- `services/gateway-coordinator/`;
- `simulators/gateway/`;
- `contracts/events/`;
- `tests/e2e/`.

## Não objetivos da próxima fatia

- não definir preço, duração, unidades ou validade;
- não criar fluxo de cadastro, pagamento ou fechamento;
- não congelar um novo layout final de Challenge/Decision;
- não implementar validação final da Decision dependente de campos bloqueados;
- não finalizar discovery, enrollment ou capabilities de gateway;
- não implementar LED, relé, catraca, tomada ou comando de óculos;
- não criar frontend administrativo definitivo;
- não iniciar hardware ou firmware.

## Critérios de aceite

- retries preservam claim e `transaction_id`;
- cada tentativa usa `challenge_nonce` novo;
- o rádio é reavaliado por sightings recentes do servidor;
- gateways elegíveis ainda não tentados são preferidos; o melhor pode ser
  reutilizado quando não houver alternativa;
- resposta de tentativa anterior não avança o estado;
- exatamente três falhas levam interação/claim a `expired` e transação a
  `cancelled`, sem reserva nem ledger;
- corrida entre timeout e sucesso tem um único vencedor;
- restart retoma pelo banco e não cria nem perde avanço de tentativa;
- eventos e logs reconstroem tentativa, gateway, nonce e desfecho;
- simuladores cobrem gateway offline, timeout, resposta tardia e troca de rádio;
- documentação, contratos, banco e backend permanecem verdes.

## Validação obrigatória

```bash
python tools/validation/validate.py
python tools/database/validate.py --docker-container <postgres-temporario>
cd apps/edge-api
go test -race ./...
go vet ./...
go build ./cmd/edge-api
```

Se migrations ou queries forem alteradas, regenerar `sqlc` 1.31.1 e provar que
o resultado versionado não divergiu. A validação PostgreSQL deve incluir
concorrência, restart e rollback.

## Protocolo de conclusão e atualização

Uma entrega só altera o estado deste arquivo depois de passar contratos, testes
e procedimentos relevantes. Na mesma PR, atualizar:

- `CURRENT_STATE.md`;
- `AGENTS.md`, quando fronteiras ou proibições mudarem;
- `README.md` e `docs/roadmap.md`;
- gate da etapa afetada;
- ADR e documentação correspondente no vault;
- contagem de migrations e evidência de CI, quando aplicável.

Não marcar trabalho como concluído apenas porque compilou.
