# ADR 0004 — Payload de advertising, expiração de descoberta e transporte de fila

Status: accepted — 2026-07-17; parcialmente substituída pela ADR 0005

> A ADR 0005 corrige a entrada do CMAC e renomeia `expires_at_local` para
> `request_ttl_seconds`. O tamanho de 22 bytes e a escolha de SSE permanecem.

## Decisão

### Payload de advertising simplificado

Os campos de `Solicitação` em `contracts/proximity/README.md` continham
redundância que não cabia no limite de 31 bytes do BLE legacy advertising
(orçamento real após AD Flags + overhead de Manufacturer Data: ~24 bytes
úteis). Duas mudanças resolvem isso:

- `ephemeral_id` e `auth_tag` são unificados em um único campo `tag` de
  8 bytes: `tag = truncate(AES-CMAC(band_key, session_nonce ‖ display_code ‖
  expires_at_local ‖ transaction_counter))`. O mesmo processo de busca por
  chave (ADR 0003) resolve identidade e autentica o payload ao mesmo tempo —
  não há necessidade de dois MACs de 64 bits separados.
- `interaction_id` deixa de ser gerado e anunciado pela pulseira. O servidor
  atribui o `interaction_id` na primeira vez que resolve um `session_nonce`
  novo, e correlaciona sightings seguintes pelo payload bruto
  (`session_nonce` + `tag`), não por um ID pré-anunciado. Gateways continuam
  reportando o payload bruto ao servidor; a atribuição de `interaction_id` é
  inteiramente uma decisão do servidor.

Payload de advertising resultante: `protocol_version`(1B) + `session_nonce`
(8B) + `tag`(8B) + `display_code`(4B) + `expires_at_local`(1B) = **22 bytes**,
com folga dentro do orçamento de ~24 bytes.

### Expiração da fase de descoberta

`expires_at_local` no advertising é um offset relativo (não timestamp
absoluto) de **60 segundos**: tempo suficiente para a pessoa soltar o botão,
verbalizar o código e o operador localizá-lo mesmo em fila cheia, sem manter
códigos obsoletos visíveis por tempo excessivo. Cabe em 1 byte (máx. 255s).
Este valor é distinto da janela de confirmação de 10s decidida na ADR 0003,
que se aplica à fase pós-claim (`awaiting_band_confirmation`).

### Transporte de tempo real da fila

Atualizações da fila global para TFTs e `operator-web` usam **Server-Sent
Events (SSE)**. A escolha estava em aberto em `contracts/openapi/README.md`.
Motivação: o canal só transporta atualizações servidor → cliente (mudanças
de estado da fila); toda mutação (claim, cancelamento) já viaja por HTTP
REST em requisições separadas. SSE roda sobre HTTP puro, tem reconexão
automática nativa via `EventSource` nos navegadores usados pelos TFTs e pelo
`operator-web`, e é mais simples de operar/depurar numa LAN local que
WebSocket, sem abrir mão de latência baixa.

## Motivação

O payload especificado originalmente em `contracts/proximity/README.md` não
respeitava o limite físico do advertising legado — um erro que só ficaria
evidente na implementação do firmware (Etapa 11), tarde demais para corrigir
sem quebrar compatibilidade. Corrigir agora, na fase de contratos,
evita retrabalho e mantém a promessa da Etapa 3 de fronteiras versionadas
antes de implementações consumidoras.

## Consequências

- `contracts/proximity/README.md` precisa refletir a lista de campos
  atualizada (sem `ephemeral_id` e `interaction_id` no advertising).
- O layout binário exato (offsets, ordem dos campos) fica em
  `contracts/proximity/binary-format.md`, criado na Etapa 3.
- `contracts/openapi/README.md` deixa de listar transporte da fila como
  aberto; a especificação executável inclui um endpoint SSE.
- `domain-model.md` não muda: `interaction_id` já era modelado como
  atribuído pelo servidor na criação da entidade (`sighting autenticado,
  interaction_id novo`); a mudança é só de quem originava o valor na
  mensagem de rádio, não da propriedade do domínio.
