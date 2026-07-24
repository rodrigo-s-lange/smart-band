# Plano da simulação comercial Smart-Band

Status: **D0–D6 concluídas; D7 parcialmente concluída; publicação externa
encerrada em 2026-07-24**.

Vault baseline desta definição:
`4e0a4cf012469795ef48be2259ab1b7083d5f474`.

## Objetivo

Entregar uma demonstração navegável para apresentar e vender a visão do
Smart-Band antes do hardware, sem representar pagamento, BLE físico, tamper,
acionamento ou políticas comerciais pendentes como funcionalidades concluídas.

Em 10–15 minutos, a demo deve contar a jornada completa: atendimento, carga de
créditos, solicitação da pulseira, seleção no gateway, confirmação pela pessoa,
liberação da atração, débito e indicadores atualizados.

## Decisões

- Streamlit é a interface exclusiva da simulação comercial.
- `apps/operator-web` continua sendo o frontend operacional definitivo.
- URL pública usada na reunião: `https://pulseira.easysmart.com.br`; o hostname
  está sem registro DNS após o encerramento de 2026-07-24.
- O i5 hospeda o laboratório; acesso LAN é a contingência.
- Dados, pessoas, pagamentos, dispositivos e valores são fictícios.
- A natureza demonstrativa fica documentada e no controle de acesso; a interface
  apresentada ao cliente não repete avisos em cada área ou display.
- Quando autorizada, a publicação usa HTTPS e autenticação por proxy/túnel
  dedicado e temporário.
- PostgreSQL, Edge API e portas do i5 não ficam públicos.
- Fixture não é decisão comercial, seed de produção ou evidência de hardware.

A [ADR 0014](../decisions/0014-streamlit-commercial-simulation.md) limita essa
decisão à demo. O gate executável está em
[demo-commercial-simulation.md](../stage-gates/demo-commercial-simulation.md).

## Arquitetura

```text
navegador da reunião
        |
        | HTTPS + autenticação
        v
pulseira.easysmart.com.br
        |
        v
proxy/túnel seguro
        |
        v
Streamlit em container no i5, somente na rede interna
        |
        +--> estado compartilhado e cenários determinísticos
        +--> pulseira, gateway e atração virtuais
        `--> Edge API apenas nas capacidades vigentes
```

O diagrama registra a topologia usada durante a publicação temporária, atualmente
desativada.

O Streamlit é apresentação. O estado do cenário não pode depender somente de
`session_state`, porque caixa, gateway e pulseira podem estar abertos em
navegadores diferentes. Um adaptador isolado da demo fornece estado
compartilhado, relógio controlável, IDs determinísticos, reset e injeção de
falhas. Ele não entra no domínio, ledger ou contratos de produção.

## Estrutura implementada

```text
apps/demo-streamlit/
  app.py
  demo_app/
    auth.py
    state.py
    views.py
  tests/
deploy/demo/
  compose.yaml
  README.md
docs/demo/
  commercial-simulation-plan.md
```

O adaptador usa SQLite somente para compartilhar o cenário da demonstração. Ele
não substitui PostgreSQL, Edge API ou ledger do produto.

## Navegação

```text
Visão Geral | Atendimento | Operação | Dispositivos |
Alertas | Controle da Demo
```

- **Visão Geral:** evento, vendas, consumo, atrações, dispositivos, alertas e
  gráficos demonstrativos.
- **Atendimento:** participante/sessão, vínculo e carga de créditos.
- **Operação:** fila global, atrações, solicitações e sessões.
- **Dispositivos:** Gateways e Pulseiras, estados e simulações.
- **Alertas:** tamper, bateria, gateway, acionamento e reconciliação.
- **Controle da Demo:** fixtures, cenários de falha e reset da demonstração.

A barra superior expõe evento ativo, modo local, gateways online, pulseiras em
uso e alertas. A navegação e os rótulos não congelam a UX de produção.

## Cockpit principal

A página inicial implementa o conceito do esboço aprovado:

- pulseira com OLED azul 128×32, textos grandes, gestos de um/dois cliques,
  saldo, código, confirmação e tempo;
- gateway com TFT 170×320 vertical, atração fixa, fila, seleção, cronômetro e
  estados operacionais por cor;
- painel de atendimento com pessoa fictícia, vínculo, pacote e pagamento;
- linha do tempo dos eventos e mudanças de estado.

O cockpit é uma composição didática. Caixa, gateway físico e pulseira real não
precisam reproduzir essa disposição.

## Cenários

### S1 — caminho feliz comercial

1. criar sessão fictícia ou selecionar participante fictício;
2. vincular pulseira virtual disponível;
3. criar venda pendente e selecionar pacote/forma de pagamento;
4. confirmar manualmente o pagamento simulado;
5. creditar carteira fictícia;
6. executar clique duplo na pulseira;
7. gerar código visual e solicitação na fila global;
8. selecionar código e atração no gateway;
9. mostrar atração, custo e duração na pulseira;
10. confirmar na pulseira;
11. reservar créditos;
12. simular comando e ack positivo;
13. converter reserva em débito uma única vez;
14. iniciar cronômetro de 5 minutos, atualizar saldo, timeline e dashboard.

Na fixture, solicitação e confirmação têm janelas independentes de 30 segundos.
O código expirado sai de todos os TFTs e rotaciona. Não existe renovação ou novo
débito automático. Encerramento pela pulseira não estorna o crédito e exige
confirmação operacional no gateway antes de a atração voltar a `LIVRE`.
Essa confirmação também libera a pulseira para nova atividade e delimita a
métrica de duração do uso; a regra vale para atrações temporizadas ou não.
Na contingência aceita, outro gateway do site pode fechar o uso. Como último
recurso, a nova atividade fecha somente a participação anterior da pulseira e
marca a duração como estimada.

### S2 — falha de rádio

O primeiro gateway de rádio falha antes da entrega. A mesma interação e
transação seguem para nova tentativa por outro gateway elegível, sem nova carga,
reserva ou cobrança.

### S3 — acionamento não executado

O gateway retorna `not_executed`; a demo não cria débito nem inventa segundo
acionamento.

### S4 — resultado ambíguo

A liberação exige reconciliação auditada. Nenhuma repetição física automática é
apresentada.

### S5 — diferenciais conceituais

- vibracall e padrões visuais acessíveis;
- remoção simulada e ciclo do alerta;
- gamificação determinística com bônus fictício;
- concentração BLE agregada por zona;
- operação local durante indisponibilidade da internet.

S5 deve usar o selo `Conceito simulado`. Não usa protocolo tamper v2 aceito,
sorteio real, beacon real ou rastreamento individual.

## Fixture VRPlay Demo

- um tenant, um site e um evento ativo;
- 8 gateways virtuais;
- 32 pulseiras virtuais;
- atrações fictícias cobrindo LED, relé, catraca e comando VR;
- participantes e contatos claramente fictícios;
- pagamentos, preços e créditos marcados como simulados;
- relógio e gerador de IDs injetáveis;
- reset idempotente para a mesma baseline.

Os 5 minutos por crédito, 30 segundos de TTL e mensagens dos displays são
parâmetros aprovados para a apresentação. Continuam sujeitos à validação da
VRPlay antes de virar contrato do produto.

Os números representam uma amostra dentro do caso informado de 7–10 gateways e
25–40 pulseiras. Não constituem limite de escala ou configuração aprovada.

## Etapas D0–D7

### D0 — preparação e gate de publicação

Entradas: data da reunião, público autorizado, responsável pelo DNS, método de
autenticação, marca e atrações que podem aparecer.

Saída: checklist aprovado, inventário e nenhum segredo no repositório.

### D1 — fundação visual e navegação

- criar app isolado, tema, páginas e selo de simulação;
- criar fixture e reset;
- validar carregamento sem Edge API e sem internet.

Gate: todas as páginas abrem com dados fictícios.

### D2 — estado compartilhado e dispositivos virtuais

- modelar estado fora da sessão do navegador;
- implementar pulseira, gateway, atração e timeline virtuais;
- sincronizar pelo menos três navegadores;
- injetar relógio, IDs e falhas.

Gate: todos veem o mesmo cenário e o reset não deixa resíduo.

### D3 — caminho feliz

- implementar S1 completo;
- reutilizar Edge API somente onde o contrato vigente permitir;
- marcar transições comerciais simuladas;
- bloquear duplo clique, dupla carga e duplo débito.

Gate: S1 passa três vezes após reset com resultado determinístico.

### D4 — operação e gestão

- completar dashboard, Dispositivos, Alertas e Relatórios;
- demonstrar cadastro/capacidades de gateway e vínculo de pulseira;
- reconciliar gráficos com a timeline.

Gate: todo agregado pode ser explicado pelos eventos exibidos.

### D5 — resiliência e diferenciais

- implementar S2–S5;
- distinguir validado, simulado e conceitual;
- demonstrar offline, retry, `not_executed` e reconciliação.

Gate: falhas não criam efeito financeiro ou físico duplicado.

### D6 — empacotamento e acesso seguro

- container, healthcheck, logs e inicialização automática;
- bind interno, HTTPS, autenticação e segredos externos ao Git;
- domínio público por proxy/túnel e fallback LAN;
- runbook para ativar e encerrar o acesso externo.

Gate: externamente somente HTTPS autenticado está acessível; desligar o túnel
preserva a demo LAN.

### D7 — ensaio e aceite

- roteiro comercial de 10–15 minutos e técnico opcional;
- três ensaios completos;
- teste em outro notebook e rede móvel;
- vídeo de contingência e checklists.

Gate: o roteiro principal termina mesmo sem internet externa.

## Critérios globais de pronto

- instalação reproduzível a partir do Git;
- somente dados fictícios;
- HTTPS autenticado no domínio;
- reset total em até 10 segundos;
- estado comum a pelo menos três navegadores;
- S1 completo em até 5 minutos e apresentação em até 15;
- S2–S4 sem efeitos duplicados;
- nenhum segredo, banco ou API interna exposto;
- fallback LAN e vídeo testados;
- distinção visível entre vigente, simulado e conceitual.

## Fora do escopo

- frontend definitivo da appliance;
- cartão, Pix, fiscal ou comissão reais;
- BLE/GATT, gateway, relé ou pulseira físicos;
- protocolo tamper v2 aceito ou firmware;
- sorteio ou promoção comercial real;
- rastreamento individual por BLE;
- ambiente público permanente ou SLA de produção;
- resolver decisões D1–D17 pelas fixtures.

## Processo no dia da reunião

1. verificar i5, containers, relógio e espaço em disco;
2. resetar fixture e validar o cockpit pela LAN;
3. validar HTTPS e autenticação pelo domínio;
4. preparar abas de Visão Geral, Gateway e Pulseira;
5. executar S1 e resetar novamente antes da reunião;
6. apresentar S1 e no máximo dois cenários adicionais;
7. registrar respostas como decisões D1–D18, sem editar regras ao vivo;
8. salvar feedback e encerrar o acesso externo após o uso.

## Parâmetros aprovados para esta reunião

- reunião na terça-feira, com 30–60 minutos;
- público misto comercial, operacional e técnico;
- atrações Corrida, Boxe, Explorador e Tiro;
- 1 crédito por atração e R$ 20 por crédito, exclusivamente como fixture;
- autenticação temporária por senha;
- Cloudflare Tunnel no i5 e contingência LAN;
- controle manual dos cenários, sem autoplay;
- desligamento do acesso externo após a janela da reunião.

Pendências de D7: testar outro notebook, rede móvel e TV e executar os checklists
do dia anterior e do dia da reunião. Roteiros, três ensaios cronometrados e
vídeo offline já foram validados.

Roteiro, checklists e matriz de contingência:
[meeting-runbook.md](meeting-runbook.md).
