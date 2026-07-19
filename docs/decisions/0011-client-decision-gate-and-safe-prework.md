# ADR 0011 — Gate de decisões do cliente e trabalho técnico seguro

Status: aceita — 2026-07-18

## Resultado da autorização técnica

O motor de retry autorizado por esta ADR foi integrado pela PR 10, merge
`b02d73f6b66c3010187101c416407a43fcdfe990`. A ADR continua vigente como gate
das decisões do cliente, mas não autoriza outra implementação funcional. O
próximo marco é responder D1–D8 e atribuir responsáveis/prazos a D9–D12.

## Contexto

O núcleo transacional já define autoridade, claim, rádio, reserva e
idempotência. Cadastro, pagamentos, validade, preço, duração, conteúdo exibido,
acionamento e campanhas ainda dependem do cliente. Implementar o Challenge final
ou contratos administrativos completos agora congelaria suposições comerciais.

O retry anterior à entrega do Challenge, por outro lado, já possui invariantes
definidos e pode ser desenvolvido sem conhecer o conteúdo comercial do payload.

## Decisão

- As decisões listadas em
  [client-decisions-pending.md](../product/client-decisions-pending.md) formam um
  gate obrigatório.
- Nenhuma resposta pendente pode ser inferida por agente, fixture ou conveniência
  técnica.
- A entrega técnica então autorizada era o motor de retry de rádio com uma porta
  que tratasse versão e payload como opacos; seu resultado está registrado no
  início desta ADR.
- Retry preserva claim, `transaction_id`, atração e gateway de liberação; muda
  tentativa, `radio_gateway_id`, `challenge_nonce` e lease.
- O formato final de Challenge/Decision e os contratos administrativos
  dependentes permanecem bloqueados.
- Hardware e firmware permanecem fora do escopo.

## Consequências

- `CURRENT_STATE.md` é o handoff operacional canônico do Git.
- `AGENTS.md`, README, roadmap e gate da Etapa 5 devem apontar a mesma próxima
  tarefa e os mesmos não objetivos.
- Operações OpenAPI representativas dependentes do cliente recebem a extensão
  `x-smartband-status: client-decision-blocked`.
- A validação de contratos verifica contagem de migrations, documentos
  obrigatórios e marcações de bloqueio.
- Uma LLM sem histórico da conversa deve conseguir reconstruir estado, escopo,
  bloqueios, validações e definição de pronto apenas pelas fontes oficiais.

## Vault

Decisão correspondente no vault, commit
`ce99e8a5eb53d58b033016379e6128d71522b669`:

```text
07-decisoes/2026-07-18-smart-band-gate-decisoes-cliente-e-trabalho-seguro.md
```
