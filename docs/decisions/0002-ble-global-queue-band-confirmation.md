# ADR 0002 — BLE, fila global e confirmação na pulseira

Status: accepted — 2026-07-17

## Decisão

- IR é removido da arquitetura.
- Pulseira solicita interação por BLE advertising.
- Gateways alimentam uma fila global no servidor local.
- Pessoa verbaliza o código e o operador seleciona no TFT da atração.
- Servidor executa claim atômico.
- Gateway operador e gateway de rádio podem ser diferentes.
- GATT transporta atração, custo, desafio, confirmação e resultado.
- Débito ocorre somente após confirmação autenticada na pulseira.

## Motivação

A decisão elimina ambiguidade entre gateways vizinhos, preserva métricas por
atração e transforma o consentimento em parte da experiência.

## Consequências

- fila, sightings, claims e leases entram no domínio
- advertising não é canal transacional completo
- simuladores precisam cobrir concorrência e seleção errada
- OLED e botão passam a fazer parte do contrato de UX
