# AGENTS.md

Orientações obrigatórias para LLMs e agentes que trabalhem no Smart-Band.

## Missão do produto

Construir um sistema local-first de pulseiras para eventos. A pessoa solicita
uma interação por BLE, o operador escolhe o código correto em uma fila global e
a pessoa confirma a atração e o custo na própria pulseira antes do débito.

## Fontes da verdade

- `CURRENT_STATE.md`: estado operacional, próxima entrega, bloqueios e critérios
  de aceite para handoff.
- Vault: decisões, contexto, arquitetura, plano e operação.
- GitHub `rodrigo-s-lange/smart-band`: código e artefatos executáveis.
- `/home/rodrigo/projects/products/smart-band`: laboratório atual.

O laboratório pode ser descartado. Nenhuma mudança durável pode existir apenas
nele. Decisões arquiteturais relevantes também devem ser registradas no vault.

## Leitura obrigatória antes de alterar código

1. `README.md`
2. `CURRENT_STATE.md`
3. `docs/product/client-decisions-pending.md`
4. `docs/architecture/layers.md`
5. `docs/architecture/interaction-queue.md`
6. `docs/architecture/transaction-flow.md`
7. `docs/architecture/domain-model.md`
8. `docs/architecture/domain-invariants.md`
9. `contracts/proximity/README.md`
10. `docs/decisions/0001-local-first-appliance.md`
11. `docs/decisions/0002-ble-global-queue-band-confirmation.md`
12. `docs/decisions/0003-ble-protocol-parameters.md`
13. `docs/decisions/0004-advertising-payload-and-transport.md`
14. `docs/decisions/0005-protocol-correction-and-transaction-safety.md`
15. `docs/decisions/0006-single-tenant-single-site-appliance.md`
16. `docs/decisions/0007-edge-api-foundation.md`
17. `docs/decisions/0008-authenticated-sightings-and-sse.md`
18. `docs/decisions/0009-atomic-claim-and-radio-selection.md`
19. `docs/decisions/0010-gateway-as-operational-identity.md`
20. `docs/decisions/0011-client-decision-gate-and-safe-prework.md`
21. `docs/decisions/0012-radio-retry-and-opaque-transport.md`
22. `contracts/gateway/radio-dispatch.md`
23. `docs/roadmap.md`

## Decisões vigentes

- IR não faz parte da arquitetura.
- BLE advertising é usado para descoberta.
- GATT é usado para desafio, confirmação e resultado.
- O código visual seleciona uma solicitação; não autoriza débito sozinho.
- A pessoa confirma atração e custo na pulseira.
- PostgreSQL local é autoridade de saldo e ledger.
- Pulseira e gateway não debitam saldo isoladamente.
- A fila de solicitações pertence ao servidor local.
- `band_key` fica somente na pulseira e cifrada na appliance; gateway não a recebe.
- TTL de interação usa relógio da appliance, nunca o relógio do gateway.
- SSE retoma pelo `stream_sequence`; snapshot inicial vem de `GET /v1/queue`.
- O gateway operador pode ser diferente do gateway de rádio.
- O gateway cadastrado é a identidade operacional; não há login ou cadastro de
  operador humano no fluxo.
- Claim deriva `operator_gateway_id` da credencial do gateway e recebe apenas a atração.
- Claim, transaction intent e evento `interaction.claimed` nascem atomicamente.
- Retry anterior ao Challenge preserva claim e `transaction_id`; cria novo
  `dispatch_id`, `challenge_nonce`, tentativa e lease. O rádio é reavaliado e
  pode ser reutilizado se não houver alternativa elegível.
- `delivered` exige confirmação técnica da escrita completa pela pulseira.
- Sem rádio elegível, a tentativa aguarda 10 segundos em `waiting_for_radio`;
  nunca usa sighting stale e falha como `no_radio_gateway` ao vencer a janela.
- Após três falhas, interação e claim ficam `expired` e a transação `cancelled`.
- Worker e fencing persistidos no PostgreSQL são autoridade; timer em memória não é.
- Rádio inicial usa sightings do servidor dos últimos 10 segundos: maior RSSI,
  maior recência e menor ID como desempate.
- A EasySmart Platform não está no caminho operacional.
- Uma appliance atende um único tenant e um único site operacional por vez.
- Um site mantém múltiplos eventos históricos e no máximo um evento ativo.
- Serviços externos são opcionais e não recebem dados pessoais por padrão.
- Hardware e firmware ESP32 vêm depois de contratos, simuladores e backend.

## Invariantes

- Um `transaction_id` causa no máximo um débito.
- Débito só é commitado depois de ack positivo e idempotente do acionamento.
- Reserva de crédito não é lançamento de ledger e pode ser liberada antes da entrega.
- Saldo e ledger mudam na mesma transação de banco.
- Uma `interaction_request` possui no máximo um claim ativo.
- Uma pulseira possui no máximo uma interação ativa inclusive em
  `actuation_failed` e `reconciliation_required`.
- Seleção usa `interaction_id`, nunca posição visual na fila.
- Código visual duplicado nunca resolve uma pulseira automaticamente.
- Advertising inválido não entra na fila.
- Identificadores permanentes não aparecem no advertising.
- Chaves de pulseira não são armazenadas em gateways.
- Timeout ou rejeição na pulseira não alteram saldo.
- `operator_gateway_id`, `radio_gateway_id` e `attraction_id` são registrados separadamente.
- Override e reconciliação registram gateway, ação, motivo e horário.
- O sistema precisa funcionar sem internet.

## Gate atual e trabalho autorizado

As decisões em `docs/product/client-decisions-pending.md` aguardam o cliente e
não podem ser resolvidas por suposição. Isso inclui cadastro, pagamentos,
validade, preço, duração, conteúdo final da pulseira, acionamento físico, perfis
administrativos, campanhas e relatórios.

O motor de retry de rádio de `contracts/gateway/radio-dispatch.md` foi integrado
na PR 10. Não há nova fatia funcional autorizada: o próximo marco é obter da
VRPlay as decisões D1–D8 e responsáveis/prazos para D9–D12 conforme
`CURRENT_STATE.md`. Não congelar Challenge/Decision final, contratos
administrativos, frontend, hardware ou firmware antes de atender o gate
correspondente.

## Fronteiras de responsabilidade

- `apps/edge-api`: domínio, persistência, autenticação, fila, ledger e API.
- `apps/operator-web`: UX local; não contém regra de saldo.
- `services/gateway-coordinator`: coordenação de sightings e rádio; não contém ledger.
- `contracts`: fronteiras versionadas antes das implementações consumidoras.
- `simulators`: primeira implementação funcional do protocolo.
- `deploy/appliance`: instalação reproduzível e sem dependência do i5.
- `firmware` e `hardware`: somente após o gate definido no roadmap.

## Ordem de implementação

1. Especificação e contratos.
2. Modelo de dados e migrations.
3. Backend local.
4. Simuladores de pulseira e gateway.
5. Frontend e fila global.
6. Testes de segurança, concorrência e recuperação.
7. Appliance piloto.
8. Gateway físico.
9. Pulseira física.

## Segurança

- Nunca commitar segredos, chaves, tokens, dumps ou `.env` reais.
- Usar chave exclusiva por pulseira.
- Proteger comparações de MAC contra timing leaks.
- Preferir tags autenticadoras de pelo menos 64 bits no MVP.
- Tratar replay, relay, tracking, clonagem, rollback e fila falsa nos testes.
- Separar por domínio todas as entradas de CMAC e testar a transcrição completa.
- Prever Secure Boot, Flash Encryption e proteção de debug para produção.
- Não afirmar chave não exportável em eFuse sem prova no MCU/API escolhidos;
  validar o caminho real usado pelo AES-CMAC.
- Dados pessoais permanecem locais por padrão.
- Backup externo precisa ser criptografado e autorizado pelo cliente.

## Regras de trabalho

- Não introduzir EasySmart Platform, cloud obrigatória, IR ou saldo autoritativo em device sem nova decisão formal.
- Não implementar como definitivas operações marcadas
  `x-smartband-status: client-decision-blocked` no OpenAPI.
- Não tratar fixture, exemplo ou schema representativo como decisão comercial.
- Não implementar um transporte antes de versionar o contrato correspondente.
- Não misturar telemetria técnica com ledger de negócio.
- Não acoplar domínio a ESP-IDF, framework web ou transporte de rede.
- Não depender de hostname, IP, volume ou caminho exclusivo do laboratório.
- Preservar migrations up/down e idempotência de seeds.
- Preferir testes determinísticos com relógio e gerador aleatório injetáveis.
- Documentar decisões com ADR quando houver mudança de fronteira ou invariante.

## Validação mínima por mudança

- executar `python tools/validation/validate.py` quando tocar contratos,
  protocolo, eventos, OpenAPI, estados ou documentação vinculada
- executar `python tools/database/validate.py` contra PostgreSQL real quando
  tocar migrations, constraints, reservas, comandos ou ledger
- formatadores e linters da linguagem
- em `apps/edge-api`: `go test -race ./...`, `go vet ./...` e `go build ./cmd/edge-api`
- regenerar `sqlc` e confirmar que o resultado versionado não divergiu
- testes unitários afetados
- testes de contrato afetados
- testes concorrentes quando tocar fila, claim, saldo ou ledger
- testes de replay/idempotência quando tocar protocolo ou transação
- atualização da documentação correspondente

Dependências da suíte de contratos ficam em
`tools/validation/requirements.txt`. A CI e o ambiente local devem executar o
mesmo entrypoint; não duplicar regras apenas no workflow.

## Definição de pronto

Uma etapa só está pronta quando código, testes, contrato, observabilidade e
procedimento operacional relevante estão coerentes. Compilar não é suficiente.
Toda entrega integrada também atualiza `CURRENT_STATE.md`, roadmap, gate da
etapa e o handoff correspondente no vault.
