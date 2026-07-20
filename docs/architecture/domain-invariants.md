# Catálogo de invariantes

Revisão manual de consistência entre domínio, protocolo e contratos. Este
catálogo não é prova formal; propriedades executáveis serão adicionadas nas
etapas de banco, backend e simuladores.

| # | Invariante | Mecanismo exigido |
|---|---|---|
| I1 | Um `transaction_id` causa no máximo um débito | `ledger_entry.transaction_id` UNIQUE |
| I2 | Saldo e ledger mudam na mesma transação PostgreSQL | commit atômico |
| I3 | Uma interação possui no máximo um claim ativo | índice único parcial/CAS |
| I4 | Seleção usa `interaction_id`, nunca posição visual | API de claim por ID |
| I5 | Código duplicado não resolve pulseira automaticamente | estado `queued_ambiguous`; claim bloqueado |
| I6 | Advertising inválido não entra na fila | CMAC validado antes da criação |
| I7 | Identificador permanente não aparece no ar | somente nonce, tag e dados efêmeros |
| I8 | Gateway não armazena chave de pulseira | chave apenas na pulseira e appliance |
| I9 | Timeout, negação ou cancelamento não criam débito | ausência de `ledger_entry` |
| I10 | Gateways operador e de rádio e atração são campos distintos | constraints e auditoria |
| I11 | O caminho operacional funciona sem internet | dependências somente LAN |
| I12 | Novos códigos aparecem no topo | projeção por `created_at DESC` |
| I13 | Retry de rádio usa novo `challenge_nonce` | tentativa versionada |
| I14 | Uma pulseira possui no máximo uma interação ativa | identidade resolvida + índice parcial |
| I15 | Todos os TFTs recebem a mesma visão lógica | projeção única via servidor/SSE |
| I16 | Dois operadores não avançam a mesma interação | claim CAS |
| I17 | Resposta atrasada não avança tentativa vigente | igualdade com `challenge_nonce` atual |
| I18 | Código verbalizado nunca autoriza débito | confirmação GATT obrigatória |
| I19 | Confirmação cobre transação, desafio, atração, gateway e custo | transcrição canônica da Decision |
| I20 | Pulseira e gateway não são autoridades de saldo | PostgreSQL local |
| I21 | Um `actuation_command_id` causa no máximo um acionamento | persistência idempotente no gateway |
| I22 | Débito só ocorre após ack positivo de acionamento | reserva convertida em ledger no ack |
| I23 | Ack ambíguo nunca gera auto-retry físico | `reconciliation_required` |
| I24 | Exceção operacional identifica o equipamento responsável | gateway autenticado + ação, motivo e horário |
| I25 | Replay do advertising não renova expiração | UNIQUE `(band_id, session_nonce)` + primeiro sighting |
| I26 | Mensagens CMAC de tipos diferentes não compartilham a mesma entrada | byte de domínio `0x01` a `0x05` |
| I27 | Reserva não é liberada enquanto o resultado físico puder ser sucesso | cancelamento bloqueado em `actuation_pending`; exige `not_executed` ou reconciliação |
| I28 | Toda liberação positiva abre um uso operacional | criação atômica após ack positivo |
| I29 | Uma pulseira nunca termina uma transição com duas participações ativas | fechamento anterior e abertura nova atômicos |
| I30 | Tempo, solicitação da pulseira ou silêncio não encerram o uso | fechamento explícito e idempotente no gateway |
| I31 | Duração por atração usa início e fechamento autoritativos da appliance | `closed_at - started_at` auditável |
| I32 | Reentrada fecha somente a participação da pulseira, nunca o grupo inteiro | vínculo de uso por pulseira + `implicit_close_on_reentry` |
| I33 | Métrica estimada nunca é apresentada como exata | `close_kind` obrigatório e segmentação nos relatórios |

## Gates para a Etapa 4

As migrations devem materializar I1, I3, I14, I21 e I25 como constraints de
banco, não como checagens separadas na aplicação. Reserva, consumo da reserva
e criação do ledger precisam de testes concorrentes. A Etapa 4 só termina com
testes que demonstrem idempotência, recuperação após reinício e ausência de
double-spend nos estados ambíguos.
