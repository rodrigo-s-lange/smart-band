# Decisões do cliente pendentes

Este arquivo é a barreira técnica autocontida para agentes que tenham acesso
somente ao repositório. O roteiro completo, as recomendações e o registro das
respostas são canônicos no vault.

Vault baseline documental desta sincronização:
`5eb042d5332e4eab88c296322c04a34c88bb0d8f`.

```text
C:\Users\Familia\vault\01-projetos\smart-band\processo-geral-e-decisoes-do-cliente.md
```

Status: **aguardando validação do cliente**.

## Contexto do primeiro piloto

- cliente: VRPlay;
- um espaço de aproximadamente 1.500 m² em shopping;
- uma appliance local e um evento ativo;
- 7 a 10 gateways;
- 25 a 40 pulseiras;
- qualquer pessoa autorizada pode operar um gateway, sem login individual no
  fluxo da atração;
- operação local independente de internet.

Os números precisam ser confirmados antes do dimensionamento final e não são
limites permanentes do produto.

## P0 — respostas que bloqueiam o próximo desenvolvimento funcional

### D1. Identificação e LGPD

Definir uso anônimo ou cadastro, campos mínimos, tratamento de menores,
responsável legal, consentimentos, retenção, marketing, exportação e exclusão.

### D2. Venda e pagamento

Definir pacotes ou quantidade livre, confirmação manual ou integrada, formas de
pagamento, cancelamento, estorno, cortesia e documento fiscal.

### D3. Semântica do crédito

Definir o que representa um crédito, validade, ordem de consumo, separação entre
pago/bônus/cortesia, devolução, transferência e recuperação de saldo.

### D4. Regra comercial das atrações

Definir por atração: custo fixo ou por duração, quantidade de créditos, tempo,
restrições, gratuidade, promoções e variação por evento/campanha.

### D5. Confirmação na pulseira

Definir a sequência que cabe no display 128x32: nome curto, créditos, duração,
aviso essencial, gesto de confirmar/cancelar e timeout.

### D6. Liberação e ack

Definir por atração: LED, relé, catraca, tomada ou protocolo do fabricante;
estado seguro; sinal que comprova entrega; e procedimento de contingência.

### D7. Tempo e falha de comunicação

Definir início, pausa, extensão e término; avisos; comportamento de sessão já
iniciada; e se novas liberações são bloqueadas sem a appliance.

### D8. Perfis e exceções administrativas

Definir quem pode confirmar/cancelar venda, conceder cortesia, transferir ou
ajustar saldo, reconciliar entrega incerta e alterar atração, preço ou gateway.
Registrar quando motivo ou segunda aprovação são obrigatórios.

## P1 — respostas necessárias antes da operação assistida

- **D9 — Fechamento e relatórios:** turno/dia, fundo, sangria, suprimento,
  conciliação, divergência, exportação e reabertura.
- **D10 — LGPD e retenção:** controlador, base legal, menores, direitos do
  titular, backups e validação jurídica do cliente.
- **D11 — Campanhas e reutilização:** o que varia entre eventos, validade,
  branding, preços, saldo e reutilização das pulseiras.
- **D12 — Suporte e continuidade:** acesso remoto, SLA, manutenção, UPS,
  backup/restore e exportação no encerramento do contrato.

## P2 — respostas antes do hardware, da demo ou do módulo opcional

- **D13 — Alertas e acessibilidade:** decidir vibracall no MVP, eventos e padrões
  táteis/visuais. Aviso importante não deve depender somente de som; display com
  texto curto, ícones e contraste pode apoiar pessoas com deficiência auditiva.
- **D14 — Tamper e segurança de menores:** decidir sensor de abertura/remoção,
  destinatário, reconhecimento, resposta e tolerância a falhas. É apoio à
  supervisão, não garantia de segurança. O v1 permanece inalterado e a proposta
  v2 está em [tamper-status.md](../../contracts/proximity/tamper-status.md).
- **D15 — Gamificação e prêmios:** separar missões/regras determinísticas de
  sorteios. Prêmios aleatórios exigem regras auditáveis e validação jurídica.
- **D16 — Ocupação por BLE:** começar por contagens agregadas dos gateways, sem
  trajetória individual. Beacons/receptores adicionais dependem de ensaio.
- **D17 — Comissão de venda:** definir beneficiário, base, reversões, teto e
  validação trabalhista/fiscal. Identidade no caixa não altera a operação anônima
  do gateway da atração.
- **D18 — Demo e domínio:** definir objetivo e prazo. No i5, usar dados fictícios,
  autenticação e proxy/túnel com TLS; não expor banco ou appliance diretamente em
  `pulseira.easysmart.com.br`.

D18 possui direção interna parcial desde 2026-07-19: objetivo comercial,
Streamlit exclusivo da simulação e URL pretendida
`https://pulseira.easysmart.com.br`. Data, público autorizado, DNS, autenticação
e implantação continuam pendentes. Ver
[commercial-simulation-plan.md](../demo/commercial-simulation-plan.md).

## O que não pode ser assumido

- recomendações do documento do cliente não são respostas aceitas;
- fixtures, exemplos e valores atuais do schema não são política comercial;
- `Attraction.default_cost` não congela preço ou duração;
- `Gateway.role` não substitui capabilities e vínculo gateway–atração finais;
- o Challenge não deve receber `units` ou `duration_seconds` por suposição;
- cadastro, pagamento, relatórios e perfis não podem ser implementados como
  definitivos sem decisão registrada.

## Consequências nos contratos

Enquanto o gate estiver aberto:

- `topUpCredits`, `createAttraction` e `provisionGateway` permanecem
  `client-decision-blocked` no OpenAPI;
- Challenge/Decision final permanece bloqueado;
- contratos administrativos de gateway e atração são representativos;
- nenhum frontend definitivo de cadastro, caixa ou configuração é autorizado;
- hardware e firmware continuam fora da etapa atual.
- o protocolo v2 de tamper, o dashboard público, comissão, gamificação e mapa de
  ocupação permanecem propostas, não funcionalidades autorizadas.

## Trabalho permitido antes das respostas

Não há nova entrega funcional autorizada. O trabalho seguro limita-se ao que
[CURRENT_STATE.md](../../CURRENT_STATE.md) permite: correções de defeito ou
segurança, manutenção de CI/testes/documentação, diagnóstico sem mudança de
regra e preparação da reunião/inventário dos equipamentos.

## Como considerar uma resposta válida

Cada decisão precisa registrar:

- opção escolhida e exceções;
- responsável que aprovou pela VRPlay;
- data da aprovação;
- pendências, documentos e equipamentos a fornecer;
- regra provisória e prazo, quando a decisão final for adiada.

## Como desbloquear uma implementação

1. registrar a resposta no vault;
2. obter validação explícita do cliente;
3. criar ou atualizar ADR;
4. versionar OpenAPI, eventos, banco ou BLE afetados;
5. definir critérios de aceite;
6. registrar a próxima fatia em `CURRENT_STATE.md`;
7. somente então implementar consumidores.
