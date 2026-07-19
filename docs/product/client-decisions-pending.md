# Decisões do cliente pendentes

Este arquivo é uma barreira técnica autocontida para agentes que tenham acesso
somente ao repositório. O questionário completo e o registro das respostas são
canônicos no vault.

Vault commit validado: `ce99e8a5eb53d58b033016379e6128d71522b669`.

```text
C:\Users\Familia\vault\01-projetos\smart-band\processo-geral-e-decisoes-do-cliente.md
```

Status: **aguardando validação do cliente**.

## O que não pode ser assumido

1. **Cadastro e LGPD** — campos obrigatórios, uso anônimo, menores, responsável,
   consentimentos, retenção, marketing, exportação e exclusão.
2. **Venda e pagamento** — pacotes, quantidade livre, confirmação manual ou
   integrada, cartão, débito, Pix, dinheiro, cancelamento, estorno e documento
   fiscal.
3. **Fechamento e conciliação** — turno ou dia, fundo de caixa, sangria,
   suprimento, relatório da adquirente, extrato Pix, divergências e exportação.
4. **Semântica do crédito** — conversão monetária, crédito pago, bônus, cortesia,
   validade, ordem de consumo, devolução, transferência e recuperação.
5. **Preço da atração** — custo fixo por uso, pacote por duração, quantidade de
   unidades, promoções, tabelas por campanha e gratuidade.
6. **Tempo** — início do contador, tolerância, pausa, extensão, término, aviso e
   comportamento durante queda de LAN ou Wi-Fi.
7. **Liberação física** — LED, relé, catraca, tomada, protocolo do fabricante,
   estado seguro e sinal que comprova entrega.
8. **Exceções e perfis** — caixa, supervisor, administrador, cortesia, ajuste,
   override, reconciliação, motivo e eventual segunda aprovação.
9. **Eventos e campanhas** — preços, validade, atrações, branding, reutilização
   de saldo, pulseiras e relatórios entre contextos.
10. **Operação e suporte** — escala, capacidade, relatórios, backup, acesso
    remoto, SLA, atualizações, UPS e exportação ao encerrar o contrato.

## Consequências técnicas

Até as respostas virarem ADR e contrato versionado:

- `topUpCredits`, `createAttraction` e `provisionGateway` são esqueletos
  representativos no OpenAPI, marcados `client-decision-blocked`;
- `Attraction.default_cost` não define a política final de preço ou duração;
- `Gateway.role` é somente uma projeção atual de inventário, não um modelo final
  de capabilities ou autorização;
- o Challenge vigente não deve ganhar `units` ou `duration_seconds` por
  suposição;
- cadastro, pagamento, relatórios e perfis administrativos não devem ser
  implementados como definitivos;
- fixtures e exemplos não são decisões comerciais.

## Trabalho permitido antes das respostas

Somente o escopo descrito em [CURRENT_STATE.md](../../CURRENT_STATE.md): motor de
retry de rádio, porta de transporte de payload opaco, simuladores, testes de
concorrência/restart e observabilidade técnica correspondente.

## Como desbloquear uma decisão

1. registrar a resposta no vault;
2. obter validação explícita do cliente;
3. criar ou atualizar ADR;
4. versionar OpenAPI, eventos, banco ou BLE afetados;
5. definir critérios de aceite;
6. somente então implementar consumidores.
