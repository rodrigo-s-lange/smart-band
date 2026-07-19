# Simulador de gateway

O primeiro adaptador executável fica em
`apps/edge-api/internal/radiosim`. Ele trata `protocol_version` e `payload` como
opacos, só retorna `delivered` quando o roteiro confirma a escrita completa e
memoriza o resultado por `dispatch_id` para que uma chamada repetida após
restart seja idempotente.

Os roteiros suportam gateway offline, conexão malsucedida, escrita não
confirmada, erro de transporte, timeout e entrega. O simulador não decide
preço, duração, conteúdo de Challenge ou acionamento físico.

Sem roteiro explícito, o adaptador falha fechado como `gateway_offline`; ele
nunca inventa confirmação de escrita.

Deve permitir múltiplas instâncias e simular:

- sightings repetidos e RSSI variável
- TFT com fila global
- seleção concorrente do mesmo código
- gateway operador diferente do gateway de rádio
- falha e fallback da sessão GATT
- acionamento aprovado ou falho
- persistência de `actuation_command_id`, ack e deduplicação após reinício
- ack ambíguo sem segundo acionamento automático
