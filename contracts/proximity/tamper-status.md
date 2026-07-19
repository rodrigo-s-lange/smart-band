# Tamper status e segurança de menores

Status: **proposta bloqueada pela decisão D14 do cliente**.

Este contrato define a semântica mínima para detectar uma pulseira possivelmente
aberta ou removida sem alterar o advertising v1 vigente. Ele não autoriza
hardware, firmware, alerta contínuo nem qualquer promessa de segurança.

## Invariantes

- o advertising v1 de 22 bytes permanece byte a byte inalterado;
- `tamper_status` precisa ser autenticado antes de produzir alerta;
- identificador permanente da pulseira não pode aparecer no rádio;
- estado desconhecido ou falha do sensor nunca pode ser interpretado como seguro;
- recepção, reconhecimento e resolução do alerta precisam ser auditáveis;
- o recurso apoia a supervisão e não garante localização, retenção física ou
  resposta humana.

## Advertising de solicitação v2 proposto (23 bytes)

A evolução v2 acrescenta um byte após `request_ttl_seconds`:

| Offset | Campo | Tipo | Bytes |
|---|---|---|---:|
| 0 | `protocol_version = 2` | uint8 | 1 |
| 1 | `session_nonce` | bytes | 8 |
| 9 | `tag` | bytes | 8 |
| 17 | `display_code` | uint32 LE | 4 |
| 21 | `request_ttl_seconds` | uint8 | 1 |
| 22 | `tamper_status` | uint8 | 1 |

O Manufacturer Data passa de 26 para 27 bytes e o pacote legacy completo de 29
para 30 bytes. Continua abaixo do limite de 31 bytes. A codificação proposta é:

| Valor | Nome | Semântica |
|---:|---|---|
| `0x00` | `secure` | sensor presente e fecho/contato dentro do esperado |
| `0x01` | `removal_detected` | abertura ou remoção detectada; exige tratamento |
| `0x02` | `sensor_fault` | sensor indisponível ou leitura incoerente |
| `0x03` | `unknown` | estado ainda não determinado |
| `0x04..0xff` | reservado | rejeitar até nova versão do contrato |

O estado participa da prova criptográfica:

```text
tag_input_v2 = 0x01 || protocol_version || session_nonce ||
               display_code_LE || request_ttl_seconds || tamper_status
```

O `protocol_version = 2` separa a transcrição da versão anterior mesmo mantendo
o domínio de advertising `0x01`. Um gateway que não conheça v2 encaminha o frame
como versão não suportada e não tenta reinterpretá-lo como v1.

## Característica GATT Device Status proposta

| Elemento | UUID |
|---|---|
| Device Status (Read/Notify) | `73b8a100-0006-4a5e-8f3d-2c9e6b7a1000` |

Payload de 14 bytes:

| Offset | Campo | Tipo | Bytes |
|---|---|---|---:|
| 0 | `protocol_version = 2` | uint8 | 1 |
| 1 | `tamper_status` | uint8 | 1 |
| 2 | `tamper_counter` | uint32 LE | 4 |
| 6 | `status_auth_tag` | bytes | 8 |

```text
status_auth_tag = CMAC64(band_key, 0x06 || bytes[0..5])
```

`tamper_counter` cresce monotonamente a cada transição e é persistido antes da
notificação. Contador repetido ou regressivo não cria novo alerta. A
característica confirma o estado de uma pulseira já resolvida; não substitui o
mecanismo de descoberta.

## Limite desta proposta

O campo no advertising de solicitação só é observado quando a pulseira solicita
uma interação. Portanto, ele não oferece alerta imediato de remoção. Antes de
prometer monitoramento contínuo será necessário versionar um frame de alerta
proativo, definir rotação de identificadores, frequência, consumo de bateria,
deduplicação, procedimento humano e retenção. Isso depende da decisão D14 e de
ensaio com o sensor real.

## Trabalho necessário para aceitar v2

1. aprovação da VRPlay sobre MVP, destinatários e resposta operacional;
2. ADR 0013 movida de proposta para aceita;
3. vetores AES-CMAC v2 calculados e validação de pacote adulterado;
4. eventos de detecção, reconhecimento, resolução e falha do sensor;
5. critérios de falsos positivos, falsos negativos e autonomia;
6. simuladores antes de qualquer implementação física.

O layout e um vetor CMAC de proposta estão disponíveis em
[`tamper-status.proposal.json`](tamper-status.proposal.json) e são verificados
pelo validador de contratos. O vetor torna a proposta reproduzível, mas seu
status `client-decision-blocked` não a transforma em protocolo aceito.
