# Simulador de pulseira

Primeira implementação executável do protocolo.

Deve simular:

- pressão longa e geração da solicitação
- código OLED
- advertising efêmero
- desafio GATT
- exibição de atração e custo
- confirmação, timeout (10s sem clique), `attention_required` após 30s e
  recebimento autenticado de Result/Cancel tardio
- AES-128-CMAC com domínio, transcrição completa, contador, replay e saldo visual (ADR 0005)
