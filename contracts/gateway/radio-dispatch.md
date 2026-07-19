# Contrato da porta de despacho de rádio

Status: contrato técnico para a próxima fatia da Etapa 5.

Este contrato cerca o motor de retry sem definir o conteúdo do Challenge. A
implementação pode usar structs Go internamente; nenhuma representação de rede
é fixada aqui.

## Comando

`Dispatch(command)` recebe:

| Campo | Tipo | Regra |
| --- | --- | --- |
| `dispatch_id` | UUID | único e persistido antes do I/O |
| `interaction_id` | UUID | imutável durante retries |
| `transaction_id` | UUID | imutável durante retries |
| `attempt` | inteiro 1–3 | igual à tentativa vigente no banco |
| `radio_gateway_id` | UUID opcional | vazio somente em `waiting_for_radio`; obrigatório em `pending` |
| `challenge_nonce` | 8 bytes | novo a cada tentativa |
| `protocol_version` | inteiro sem sinal | versão do payload, sem interpretação pela porta |
| `payload` | bytes | opaco; não registrar em log |
| `deadline` | timestamp UTC | calculado pelo relógio da appliance |

Identificadores, nonce, deadline e payload pertencem ao snapshot persistido da
tentativa. O caller não pode regenerá-los ao repetir a chamada.

## Resultado

`DispatchResult` devolve os campos de correlação `dispatch_id`,
`transaction_id`, `attempt` e `challenge_nonce`, mais exatamente um resultado:

- `delivered`: a pulseira alvo confirmou tecnicamente a escrita completa;
- `failed`: a entrega não ocorreu, com `failure_kind` igual a `gateway_offline`,
  `connect_failed`, `write_not_confirmed`, `transport_error` ou
  `no_radio_gateway`;
- `timed_out`: nenhuma confirmação técnica chegou até `deadline`.

Recebimento pelo gateway, conexão GATT e início da escrita são progresso, não
`delivered`. O adaptador simulado deve obedecer à mesma fronteira.

## Fencing e idempotência

- Apenas a linha de tentativa `pending` cujo `dispatch_id`, tentativa, nonce e
  lease continuam vigentes aceita o primeiro resultado terminal.
- Resultado duplicado devolve o estado já persistido sem repetir transição.
- Resultado de tentativa substituída é auditado como `stale` e não muda domínio.
- Corrida entre `delivered` e timeout usa CAS no PostgreSQL e tem um vencedor.
- A porta pode ser chamada novamente após crash; a autoridade é a tentativa
  persistida, não um timer ou future em memória.

## Seleção do rádio

São elegíveis gateways ativos do mesmo site com `received_at` do servidor nos
últimos 10 segundos. Ordenação: RSSI decrescente, `received_at` decrescente e ID
de protocolo crescente.

O seletor primeiro considera candidatos ainda não usados pela transação. Se o
conjunto ficar vazio, reutiliza o melhor gateway elegível. Assim, um único
gateway pode receber as três tentativas; havendo alternativas recentes, elas
são preferidas antes do reuso.

Se não existir candidato elegível, o servidor cria a próxima tentativa em
`waiting_for_radio`, com `radio_gateway_id` vazio, `dispatch_id` e nonce novos e
`selection_deadline` de 10 segundos pelo relógio da appliance. Novo sighting
elegível preenche o rádio, muda o status para `pending` e inicia um
`dispatch_deadline` também de 10 segundos. Se `selection_deadline` vencer, a
tentativa termina `failed/no_radio_gateway`, conta no limite de três e segue a
mesma transição de retry ou esgotamento. Nunca selecionar rádio por sighting
stale e nunca executar I/O enquanto `waiting_for_radio`.

## Persistência e retomada

A próxima implementação deve persistir uma linha por tentativa com, no mínimo,
os campos aplicáveis do comando, status
`waiting_for_radio | pending | delivered | failed | timed_out`, timestamps e
desfecho. A combinação `(transaction_id, attempt)` e o `dispatch_id` são únicos.

Somente em `waiting_for_radio`, `radio_gateway_id` e `dispatch_deadline` podem
estar vazios. `selection_deadline` é obrigatório nesse estado e fica vazio após
a seleção. Apenas `pending` autoriza chamada à porta.

Um worker orientado pelo banco busca trabalho em lotes com
`FOR UPDATE SKIP LOCKED` e fencing por `dispatch_id`/lease. I/O nunca mantém uma
transação aberta. No restart, tentativa abandonada com
deadline vencido é encerrada como timeout e avança pela mesma máquina de retry.

## Transições

Em `delivered`, uma única transação:

1. encerra a tentativa como `delivered`;
2. move a transação de `claimed` para `awaiting_band_confirmation`;
3. inicia a janela de confirmação pelo relógio do servidor;
4. publica `interaction.confirmation_requested` correlacionado ao despacho.

Em `failed` ou `timed_out` antes da terceira tentativa, uma única transação:

1. encerra a tentativa atual;
2. incrementa a tentativa;
3. escolhe o rádio conforme a regra acima;
4. gera novo `dispatch_id`, `challenge_nonce`, deadline e lease;
5. persiste como `pending` quando há rádio ou `waiting_for_radio` quando não há.

Na terceira falha, uma única transação:

1. define interação e claim como `expired`;
2. define `transaction_intent` como `cancelled`;
3. publica `interaction.expired` com `transaction_id`, tentativa e motivo
   `radio_attempts_exhausted`.

Reserva e ledger não são tocados por este fluxo.

## Eventos a versionar na implementação

Antes de criar o consumidor, evoluir `contracts/events/events.schema.json` e os
exemplos para representar:

- tentativa falha ou expirada: `dispatch_id`, tentativa, gateway, nonce e motivo;
- entrega e início da confirmação: `dispatch_id`, tentativa, gateway, nonce e
  horário confirmado;
- esgotamento: `transaction_id`, tentativa final e
  `radio_attempts_exhausted`.

Logs carregam `dispatch_id` e correlação, mas nunca `band_key` ou payload opaco.
