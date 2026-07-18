# Simulador de gateway

Deve permitir múltiplas instâncias e simular:

- sightings repetidos e RSSI variável
- TFT com fila global
- seleção concorrente do mesmo código
- gateway operador diferente do gateway de rádio
- falha e fallback da sessão GATT
- acionamento aprovado ou falho
- persistência de `actuation_command_id`, ack e deduplicação após reinício
- ack ambíguo sem segundo acionamento automático
