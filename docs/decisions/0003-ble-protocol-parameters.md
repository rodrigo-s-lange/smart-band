# ADR 0003 — Parâmetros do protocolo BLE e resolução de falhas operacionais

Status: histórico — substituído parcialmente pelas ADRs 0005 e 0010

> A ADR 0005 substitui as decisões sobre replay no advertising, transcrição
> autenticada, débito antes do acionamento, espera indefinida, colisão de
> código. A ADR 0010 substitui identidade humana pela identidade do gateway
> cadastrado nas operações e exceções. Este arquivo é histórico.

## Decisão

### Payload e criptografia

- Advertising e payloads GATT (desafio, confirmação, resultado) usam formato
  binário fixo, little-endian.
- Tag de autenticação: AES-128-CMAC truncada para 64 bits em todos os
  payloads autenticados (advertising, desafio, confirmação, resultado).
  Aproveita o acelerador de hardware AES presente em toda a linha ESP32
  candidata (C3/C6/S3) e atende ao mínimo de 64 bits do `AGENTS.md`.
- Contador monotônico de replay: persistido na NVS a cada incremento (não em
  checkpoints). Cálculo de endurance: uma página NVS de 4 KB comporta ~126
  escritas antes de precisar de um ciclo de erase; flash NOR típica do ESP32
  suporta ~100.000 ciclos de erase por setor. Isso dá margem de
  ~12,6 milhões de incrementos antes do desgaste — a 200 incrementos/dia,
  ~172 anos, muito acima da vida útil física esperada da pulseira. A
  simplicidade de gravar a cada incremento supera qualquer ganho de um
  esquema de checkpoint.

### Timeouts

- Valores fixos no protocolo, não configuráveis por atração nem por
  operador nesta fase (revisão exige nova versão de protocolo).
- Janela de confirmação na pulseira (`awaiting_confirmation` →
  `confirming`): **10 segundos**. Sem clique nesse intervalo, o estado vai
  para `confirmation_timeout`: o token desaparece da fila em todos os
  gateways e o processo reinicia — a pessoa precisa pressionar o botão de
  novo para criar uma **nova** `interaction_request`. Nenhuma interação
  expirada é reaproveitada.

### Confirmação e rejeição

- Não existe gesto explícito de rejeição. Um único clique curto confirma;
  ausência de clique dentro da janela é a única forma de recusa. Isso é
  intencional mesmo quando o operador seleciona o código errado: a pulseira
  mostra a atração e o custo recebidos, e cabe à pessoa não clicar se algo
  estiver errado.

### Cancelamento pelo operador

- O operador pode cancelar a qualquer momento, incluindo durante
  `awaiting_band_confirmation`. Isso exige um comando GATT novo,
  servidor → pulseira, distinto do payload de resultado normal.
- Regra de corrida: **o cancelamento do operador sempre vence** sobre uma
  decisão da pessoa que ainda esteja em trânsito, desde que a transação
  ainda não tenha alcançado o commit do ledger. Depois do commit
  (`ledger_entry` criado), um cancelamento chegando atrasado é rejeitado
  como no-op — a única via de correção pós-commit é o fluxo de
  `actuation_failed` descrito abaixo, nunca um cancelamento retroativo.

### Ordem entre débito e acionamento

- O débito ocorre em `authorized`, **antes** da confirmação de acionamento
  físico — mantém a ordem original de `transaction-flow.md`. Nenhuma
  reversão automática de débito existe no MVP.
- Se o acionamento automático falhar (`actuation_failed`), a resolução
  primária é o **operador acionar manualmente** a atração (override
  local/físico no gateway). Esse override não gera nenhum novo lançamento
  no ledger — o débito já está correto, porque o serviço será entregue.
- Overrides manuais são auditados por `operator_gateway_id` (identidade
  individual do operador fica fora de escopo por ora — ver "Postergado").
  Um padrão de overrides muito acima da média de outros gateways/terminais é
  um sinal operacional a ser observado.
- Se o override manual também não resolver (atração de fato quebrada), o
  caminho de estorno/ajuste manual — já previsto como responsabilidade de
  `apps/edge-api` — é o último recurso, sempre revisado por humano. Nenhum
  estorno é automático ou disparado por evento de sistema.
- O resultado (`transaction_id`, `result`, `remaining_balance`,
  `result_auth_tag`) só é enviado à pulseira **depois** que o acionamento —
  automático ou por override manual — for confirmado. A pulseira permanece
  em `confirming` até então, mesmo que isso ultrapasse os 10s da janela de
  clique (essa janela só se aplica à decisão da pessoa, não à espera do
  resultado). A pulseira nunca mostra sucesso antes de a pessoa poder de
  fato usar a atração. Não há timeout de protocolo para essa espera — a
  transação já está válida (debitada) independentemente de quando o
  resultado chega; é responsabilidade da UX local, não do protocolo, avisar
  a pessoa para procurar o operador caso a espera passe de um limiar visual
  (ex.: alguns segundos), sem afirmar falha.

### Aviso de conectividade fraca ("aproxime-se")

- Heurística 100% local na pulseira: se ela permanecer em
  `advertising_request` além de um limiar de tempo sem receber nenhum
  desafio GATT, exibe o aviso sozinha. Não depende de nenhuma mensagem do
  servidor — funciona mesmo no pior caso de rádio (nenhum gateway ao
  alcance).

### Retry do lease de claim

- Até **3 tentativas** de escolha de `radio_gateway_id` em caso de falha de
  rádio, reavaliando o sighting de melhor RSSI a cada tentativa. Esgotadas
  as tentativas, a interação expira normalmente (mesmo caminho de
  `expired`).
- Cada tentativa gera seu próprio `challenge_nonce`. O servidor só aceita a
  resposta cujo `challenge_nonce` corresponde à tentativa em aberto;
  respostas de tentativas antigas chegando atrasadas são descartadas sem
  afetar a tentativa vigente. Isso substitui a necessidade de uma janela de
  carência separada.

### Código visual duplicado

- `display_code` é gerado pela própria pulseira; o servidor nunca solicita
  regeneração — não existe comando de protocolo para isso.
- Ao detectar duas `interaction_request` ativas com o mesmo `display_code`,
  o servidor retém a publicação da segunda na fila visível (não aparece
  para os operadores) até a primeira ser resolvida (claim, expiração ou
  cancelamento). A pulseira da segunda pessoa continua anunciando
  normalmente e não é informada da retenção.

### Resolução de identidade da pulseira

- `ephemeral_id = truncate(AES-CMAC(band_key, session_nonce))`. Como
  `session_nonce` já é gerado pela pulseira a cada solicitação e viaja em
  claro no payload, o servidor resolve a identidade permanente testando a
  chave de cada pulseira provisionada/ativa na sessão do evento atual contra
  o `session_nonce` recebido, até achar a que reproduz o `ephemeral_id`
  informado (comparação em tempo constante, sem short-circuit por byte, para
  não vazar informação por timing).
- Sem esquema de janela/contador: `session_nonce` elimina o problema de
  drift que um esquema baseado no contador monotônico teria. O universo de
  pulseiras ativas por evento é limitado (milhares, não milhões) e a
  resolução só ocorre uma vez por `interaction_id` novo — sightings
  repetidos do mesmo `interaction_id` reusam o resultado em cache, não
  disparam nova busca.
- `auth_tag` continua autenticando o payload completo (incluindo o contador
  monotônico), garantindo replay protection independente da resolução de
  identidade.

## Postergado (fora do escopo desta ADR)

- Características e UUIDs GATT: definição mecânica, gerada na Etapa 3
  (contratos executáveis), não é uma decisão de arquitetura.
- Identidade individual de operador (login/PIN por pessoa): mantido como
  `operator_gateway_id` por enquanto. Revisar com um novo ADR se auditoria
  por terminal se mostrar insuficiente contra fraude/suborno.
- Store-and-forward do ack de acionamento no firmware do gateway: não é
  requisito desta ADR porque o débito não depende mais desse ack (ocorre
  antes). Ainda assim, gateways devem persistir e reenviar confirmações de
  acionamento quando possível, para fortalecer a auditoria de
  `actuation_failed` — decisão de implementação fica para a Etapa 10.

## Motivação

Consolidar em uma decisão formal os parâmetros marcados como "ainda não
congelados" em `contracts/proximity/README.md`, mais as lacunas encontradas
na verificação exaustiva de `docs/architecture/domain-invariants.md`,
priorizando nesta ordem: (1) nunca debitar sem o serviço ser entregue ou
explicitamente resolvido por um operador identificável, (2) nenhuma lógica
automática de movimentação de dinheiro, reduzindo superfície de bug ou
fraude, (3) simplicidade de teste — valores fixos, sem configuração
dinâmica nesta fase.

## Consequências

- Fila e protocolo ganham dois elementos novos: comando GATT de
  cancelamento e retenção de publicação por colisão de `display_code`.
- Falha de acionamento sempre depende de um humano (override do operador ou
  estorno manual) — nenhuma reversão automática existe no MVP.
- Sem identidade individual de operador, a auditoria de override fica em
  nível de gateway/terminal; abuso detectado nesse nível é o gatilho para um
  ADR futuro de login individual.
- Firmware da pulseira precisa implementar a heurística local de
  "aproxime-se" sem depender de sinal do servidor.
- `challenge_nonce` passa a ser também o mecanismo de descarte de respostas
  atrasadas de tentativas de retry — não é preciso um campo de janela de
  carência separado.
- `interaction_request` expirada por `confirmation_timeout` nunca é
  reaberta; uma nova solicitação exige nova pressão longa do botão.
