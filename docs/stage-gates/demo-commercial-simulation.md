# Gate da demonstração comercial

Status: **D0–D5 concluídas; D6 em execução; D7 pendente** — 2026-07-19.

Este gate acompanha uma trilha paralela. Marcar itens aqui não muda o estado das
Etapas 5–7 do produto.

## D0 — preparação

- [x] data e duração registradas;
- [x] público e responsável comercial definidos;
- [x] identidade visual e atrações autorizadas;
- [x] responsável por DNS e autenticação definido;
- [x] nenhum segredo versionado.

## D1 — fundação

- [x] `apps/demo-streamlit` isolado;
- [x] navegação e selo de simulação;
- [x] fixture e reset idempotente;
- [x] páginas carregam offline com dados fictícios;
- [x] testes de smoke aprovados.

## D2 — estado e dispositivos

- [x] estado fora de `session_state`;
- [x] três consumidores compartilham o mesmo cenário persistido;
- [x] pulseira, gateway, atração e timeline virtuais;
- [x] relógio, IDs e falhas controláveis;
- [x] reset não deixa evento ou sessão residual.

## D3 — caminho feliz

- [x] S1 executa carga, solicitação, confirmação, ack e débito;
- [x] transições fictícias estão identificadas;
- [x] simulações permanecem isoladas dos contratos e consumidores de produção;
- [x] três repetições após reset são determinísticas;
- [x] duplo clique não duplica carga, reserva ou débito.

## D4 — gestão

- [x] Visão Geral, Dispositivos, Alertas e Controle da Demo;
- [x] gateway mostra friendly name, atrações e capacidades;
- [x] pulseira mostra estado, vínculo e saldo;
- [x] gráficos derivam do mesmo estado persistido da timeline.

## D5 — falhas e conceitos

- [x] S2 retry de rádio sem segunda transação;
- [x] S3 `not_executed` sem débito;
- [x] S4 resultado ambíguo em reconciliação;
- [x] S5 marcado como conceito simulado;
- [x] nenhum cenário cria efeito duplicado.

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

Evidência D1–D5 em 2026-07-19:

- `python -m pytest tests -q`: 7 testes aprovados;
- `AppTest`: carregamento do app sem exceção;
- `test_reset_is_deterministic_and_shared`: três consumidores e reset sem
  resíduo;
- `test_happy_path_is_repeatable_after_three_resets`: três execuções completas;
- testes de idempotência, `not_executed`, resultado ambíguo, fallback e tamper;
- Chrome headless: S1 completo, estado final `LIBERADO` e saldo de 5 para 4;
- `/_stcore/health`: resposta `ok`.

Plano canônico:
[commercial-simulation-plan.md](../demo/commercial-simulation-plan.md).
