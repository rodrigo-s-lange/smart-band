# Catálogo de invariantes

Consolidação de todos os invariantes já declarados em `AGENTS.md`,
`docs/architecture/interaction-queue.md`, `docs/architecture/transaction-flow.md`
e `contracts/proximity/README.md`, cruzados com a máquina de estados de
[domain-model.md](domain-model.md). Cada invariante foi verificado contra
todas as transições do modelo de domínio (checagem exaustiva, ver seção
final). Nenhuma mudança de fronteira ou autoridade foi introduzida — este
documento apenas organiza e verifica o que já estava decidido.

## Catálogo

| # | Invariante | Fonte | Escopo | Mecanismo de aplicação |
|---|---|---|---|---|
| I1 | Um `transaction_id` causa no máximo um débito | AGENTS, transaction-flow | `transaction_intent` → `ledger_entry` | unicidade de `ledger_entry.transaction_id` (1:1) |
| I2 | Saldo e ledger mudam na mesma transação de banco | AGENTS, transaction-flow | transição `authorized` → `completed` | commit atômico único |
| I3 | Uma `interaction_request` possui no máximo um claim ativo | AGENTS, interaction-queue | `interaction_claim` | compare-and-swap / índice único parcial (`status = active`) |
| I4 | Seleção usa `interaction_id`, nunca posição visual na fila | AGENTS, interaction-queue | claim | claim referencia `interaction_id`, não índice de linha |
| I5 | Código visual duplicado nunca resolve uma pulseira automaticamente | AGENTS, interaction-queue | `discovered` → `queued` | ADR 0003: servidor retém a publicação da 2ª interação colidente até a 1ª resolver; pulseira nunca é avisada |
| I6 | Advertising/payload inválido não entra na fila / não é exibido | AGENTS, interaction-queue | pré-`discovered` | validação de `auth_tag` antes de criar `interaction_request` |
| I7 | Identificadores permanentes não aparecem no advertising | AGENTS, proximity | criação de `interaction_request` | apenas `session_nonce` e `tag` são transmitidos (ADR 0004); resolução para identidade permanente ocorre só no servidor, por busca de chave (ADR 0003) |
| I8 | Chaves de pulseira não são armazenadas em gateways | AGENTS, proximity | todo o fluxo | chave exclusiva só existe em pulseira e servidor |
| I9 | Timeout ou rejeição não alteram saldo | AGENTS, transaction-flow | `awaiting_band_confirmation` → `confirmation_timeout`; `confirmed_pending_validation` → `denied` | "rejeição" é a validação de saldo/regras do servidor pós-confirmação (`denied`), não um gesto da pulseira (ADR 0003) — nenhum dos dois cria `ledger_entry` |
| I10 | `operator_gateway_id`, `radio_gateway_id` e `attraction_id` são registrados separadamente | AGENTS, interaction-queue | `interaction_claim` / `transaction_intent` | campos distintos, nunca colapsados em um único `gateway_id` |
| I11 | Sistema funciona sem internet | AGENTS, ADR 0001 | todo o fluxo | nenhuma dependência de rede externa no caminho de autorização |
| I12 | Novos códigos aparecem no topo da fila | interaction-queue | `queued` | ordenação por `created_at` desc na projeção da fila |
| I13 | Claim possui lease e expira se o rádio falhar | interaction-queue | `claimed` → `awaiting_band_confirmation` \| `queued` | `lease_expires_at` + até 3 tentativas (ADR 0003), cada uma com `challenge_nonce` próprio |
| I14 | Uma pulseira possui no máximo uma interação ativa | interaction-queue | criação de `interaction_request` | servidor resolve identidade via busca de chave por `session_nonce` (ADR 0003) e rejeita nova `discovered` se já houver uma ativa não terminal |
| I15 | Todos os TFTs recebem a mesma visão lógica da fila | interaction-queue | projeção da fila | fonte única de leitura (servidor), sem estado local divergente por gateway |
| I16 | Dois operadores nunca avançam a mesma interação (claim por CAS) | interaction-queue | `queued` → `claimed` | mesmo mecanismo de I3 |
| I17 | Falha de rádio libera lease para retry mas não cria segundo `transaction_id` após confirmação | interaction-queue | `claimed` ↔ `queued` | retry reutiliza o mesmo `transaction_intent`; respostas de tentativas antigas são descartadas por não baterem o `challenge_nonce` vigente (ADR 0003) |
| I18 | Código verbalizado não autoriza débito sozinho | transaction-flow, proximity | `discovered`/`queued` | débito só ocorre após `awaiting_band_confirmation` → `authorized` |
| I19 | Confirmação é vinculada à atração, custo e transação | transaction-flow, proximity | desafio/resposta GATT | `band_auth_tag` cobre `transaction_id`, `attraction_id`, `amount` (ver proximity/README) |
| I20 | Gateway e pulseira não são autoridades do saldo | transaction-flow, AGENTS | todo o fluxo | saldo só é lido/escrito pelo servidor (PostgreSQL) |
| I21 | Falha de acionamento é auditada separadamente do débito | transaction-flow | `authorized` → `actuation_failed` | `ledger_entry` já existe; resolução é `actuation_override` manual do operador ou estorno/ajuste manual — nunca reversão automática (ADR 0003) |
| I22 | Servidor local valida todas as provas criptográficas | proximity | todas as transições autenticadas | nenhuma decisão de estado depende de validação feita em gateway ou pulseira |

## Verificação exaustiva contra as transições

Cada transição da máquina de estados de `interaction_request` foi checada
contra os 22 invariantes acima. Resultado:

- **Sem violações encontradas** nas transições já modeladas — todas as
  transições que criam `ledger_entry` passam obrigatoriamente por
  `awaiting_band_confirmation` → `authorized`, o que satisfaz I1, I2, I9,
  I18, I20 simultaneamente.
- **I3/I16 dependem de um único mecanismo de banco** (índice único parcial
  ou CAS explícito) — se implementado como duas checagens separadas (uma
  para "sem claim ativo" e outra para "operador único"), existe uma janela de
  corrida entre elas. Recomendação para a Etapa 4 (migrations): a unicidade
  deve ser uma constraint de banco, não apenas lógica de aplicação. Isto não
  é uma lacuna de decisão, é uma nota de implementação a carregar para a
  Etapa 4.
- **I17 e a janela de carência do lease**: resolvido pela ADR 0003 —
  respostas de tentativas antigas trazem o `challenge_nonce` da tentativa
  errada e são descartadas, sem precisar de uma janela de tempo separada.
- **I21 e o lado da pulseira**: resolvido pela ADR 0003 — a pulseira nunca
  fica sabendo de uma falha intermediária porque o resultado só é liberado
  depois que o acionamento (automático ou `actuation_override`) é
  confirmado. Não há mais incoerência de saldo visual: a pulseira
  simplesmente continua esperando em `confirming`.

Com a ADR 0003 (incluindo o adendo de resolução de identidade via busca de
chave por `session_nonce`), todas as lacunas da Etapa 2 estão fechadas. Não
há pendência de domínio conhecida bloqueando a Etapa 3.
