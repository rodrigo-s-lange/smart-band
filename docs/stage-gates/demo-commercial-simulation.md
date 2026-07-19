# Gate da demonstração comercial

Status: **planejada; D0–D7 não iniciadas** — 2026-07-19.

Este gate acompanha uma trilha paralela. Marcar itens aqui não muda o estado das
Etapas 5–7 do produto.

## D0 — preparação

- [ ] data e duração registradas;
- [ ] público e responsável comercial definidos;
- [ ] identidade visual e atrações autorizadas;
- [ ] responsável por DNS e autenticação definido;
- [ ] nenhum segredo versionado.

## D1 — fundação

- [ ] `apps/demo-streamlit` isolado;
- [ ] navegação e selo de simulação;
- [ ] fixture e reset idempotente;
- [ ] páginas carregam offline com dados fictícios;
- [ ] testes de smoke aprovados.

## D2 — estado e dispositivos

- [ ] estado fora de `session_state`;
- [ ] três navegadores compartilham cenário;
- [ ] pulseira, gateway, atração e timeline virtuais;
- [ ] relógio, IDs e falhas controláveis;
- [ ] reset não deixa evento ou sessão residual.

## D3 — caminho feliz

- [ ] S1 executa carga, solicitação, confirmação, ack e débito;
- [ ] transições fictícias estão identificadas;
- [ ] funções reais usam somente contratos vigentes;
- [ ] três repetições após reset são determinísticas;
- [ ] duplo clique não duplica carga, reserva ou débito.

## D4 — gestão

- [ ] dashboard, Dispositivos, Alertas e Relatórios;
- [ ] gateway mostra friendly name, atrações e capacidades;
- [ ] pulseira mostra estado, vínculo e saldo;
- [ ] gráficos reconciliam com a timeline.

## D5 — falhas e conceitos

- [ ] S2 retry de rádio sem segunda transação;
- [ ] S3 `not_executed` sem débito;
- [ ] S4 resultado ambíguo em reconciliação;
- [ ] S5 marcado como conceito simulado;
- [ ] nenhum cenário cria efeito duplicado.

## D6 — publicação

- [ ] containers, healthcheck e logs;
- [ ] serviço ligado apenas à rede interna;
- [ ] HTTPS e autenticação no domínio;
- [ ] banco e API interna não expostos;
- [ ] fallback LAN testado;
- [ ] runbook para encerrar o acesso público.

## D7 — reunião

- [ ] roteiro comercial até 15 minutos;
- [ ] roteiro técnico opcional;
- [ ] três ensaios completos;
- [ ] notebook alternativo e rede móvel testados;
- [ ] vídeo de contingência;
- [ ] checklist do dia executado.

## Evidência necessária

Cada checkbox concluído deve apontar para teste, captura, log, commit ou runbook.
“Funcionou uma vez” não conclui etapa. O gate final exige:

- `python tools/validation/validate.py`;
- testes do app via `streamlit.testing.v1.AppTest` ou equivalente vigente;
- teste automatizado do estado compartilhado, reset e idempotência;
- inspeção de portas e autenticação no i5;
- execução cronometrada do roteiro completo.

Plano canônico:
[commercial-simulation-plan.md](../demo/commercial-simulation-plan.md).
