# ADR 0008 — Sightings autenticados, proteção de chaves e SSE retomável

Status: accepted — 2026-07-18

## Contexto

O contrato já fixava advertising BLE de 22 bytes, resolução de identidade por
busca de chave e fila global via SSE. Faltavam decisões executáveis sobre onde
proteger `band_key`, qual relógio governa a expiração, como serializar sightings
concorrentes e como um TFT retoma o stream sem perder mudanças.

## Decisão

- a API aceita somente payload v1 com 22 bytes, TTL de 60 segundos e
  `display_code` Crockford Base32 de 30 bits; os dois bits superiores são
  reservados e precisam ser zero
- a busca de identidade considera somente pulseiras atribuídas a uma sessão
  ativa do evento ativo; todas as candidatas são verificadas antes do resultado
- o gateway nunca recebe `band_key`; ele envia o advertising bruto autenticado
  pela própria credencial e seu `gateway_id` precisa coincidir com a credencial
- `band_key` é AES-128 e permanece cifrada no PostgreSQL em envelope
  AES-256-GCM v1, com AAD igual ao UUID da pulseira
- a KEK de 256 bits não fica no banco nem no repositório; a appliance a lê de
  arquivo montado por `SMARTBAND_BAND_KEY_KEK_FILE`
- `received_at` do servidor governa `first_authenticated_at` e `expires_at`; o
  horário informado pelo gateway é preservado em `gateway_observed_at`, mas não
  controla autorização nem TTL
- `(band_id, session_nonce)` continua sendo a chave durável de deduplicação;
  advertising repetido cria outro sighting, retorna o mesmo `interaction_id` e
  jamais renova a expiração
- criação, colisão de código, sighting e outbox são uma única transação
  PostgreSQL, serializada por locks consultivos de pulseira e código visual
- o outbox recebe `stream_sequence` monotônica. SSE usa essa sequência em `id:`
  e aceita `Last-Event-ID`; o cliente obtém o snapshot por `GET /v1/queue` antes
  de abrir ou retomar o stream

## Consequências

- payload inválido ou não resolvido retorna `resolved=false` e não toca fila,
  sighting ou outbox
- chaves duplicadas capazes de autenticar o mesmo advertising são erro de
  provisionamento, nunca uma resolução automática
- restaurar apenas o banco não basta para operar: backup/restore precisa tratar
  a KEK separadamente, com acesso restrito e teste de recuperação
- provisioning seguro precisa produzir o envelope v1 e permanece uma entrega
  posterior da Etapa 5
- expiração descoberta é varrida durante ingestão e polling SSE; o snapshot
  também filtra por `expires_at`, mesmo antes da próxima varredura persistente
