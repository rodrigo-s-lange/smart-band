# Gate da demonstração comercial

Status: **D0–D6 concluídas; D7 parcialmente concluída** — 2026-07-19.

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
- [x] navegação e identificação concentrada no acesso/documentação;
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

- [x] containers, healthcheck e logs;
- [x] serviço ligado apenas à rede interna;
- [x] HTTPS e autenticação no domínio;
- [x] banco e API interna não expostos;
- [x] fallback LAN testado;
- [x] runbook para encerrar o acesso público.

## D7 — reunião

- [x] roteiro comercial até 15 minutos —
  [meeting-runbook.md](../demo/meeting-runbook.md);
- [x] roteiro técnico opcional —
  [meeting-runbook.md](../demo/meeting-runbook.md);
- [x] três ensaios completos — 14,39 s, 14,41 s e 14,41 s, todos com saldo 4,
  gateway `LIVRE` e reset limpo;
- [ ] notebook alternativo e rede móvel testados;
- [x] vídeo de contingência — 35,32 s, 1600×900, reprodução local validada com
  o navegador em modo offline;
- [ ] regressão da ADR 0015: impedir nova solicitação da pulseira até o
  fechamento no gateway, inclusive após `00:00` ou pedido antecipado;
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

- `python -m pytest tests -q`: 10 testes aprovados;
- `AppTest`: carregamento do app sem exceção;
- `test_reset_is_deterministic_and_shared`: três consumidores e reset sem
  resíduo;
- `test_happy_path_is_repeatable_after_three_resets`: três execuções completas;
- testes de idempotência, `not_executed`, resultado ambíguo, fallback e tamper;
- Chrome headless: S1 completo, estado final `LIBERADO` e saldo de 5 para 4;
- `/_stcore/health`: resposta `ok`.
- inspeção visual do OLED 128×32 e TFT 170×320 em código, confirmação e sessão;
- testes de TTL de 30 s, rotação, sessão de 5 min, encerramento e `OK` do gateway.

Evidência D6 em 2026-07-19:

- PR 14 integrada com os workflows `Commercial Demo` e `Contracts` verdes;
- imagem construída e container saudável no i5;
- `ss` confirmou bind em `127.0.0.1:8501` após a validação;
- túnel Cloudflare exclusivo para `pulseira.easysmart.com.br`;
- healthcheck HTTPS externo aprovado;
- senha incorreta recusada e senha correta aceita;
- S1 completo executado pelo domínio público;
- healthcheck LAN aprovado em `192.168.0.121:8501` durante a contingência e
  bind de loopback restaurado em seguida;
- fixture restaurada após o teste público;
- runbook de ativação e encerramento em `deploy/demo/README.md`.

Evidência parcial de D7 em 2026-07-19:

- roteiro comercial de 12 minutos, roteiro técnico de 5 minutos, falas,
  checklists e matriz de contingência em
  [meeting-runbook.md](../demo/meeting-runbook.md);
- três ensaios pelo domínio público concluídos em 14,39 s, 14,41 s e 14,41 s;
- cada ensaio percorreu cadastro, cinco créditos, solicitação, seleção,
  confirmação, liberação, débito único, encerramento antecipado, `OK` do gateway
  e reset final sem resíduo;
- vídeo `smart-band-contingencia.webm`, com 35,32 s e resolução 1600×900,
  armazenado fora do Git para cópia ao notebook da reunião;
- reprodução do vídeo validada em Chrome com rede desabilitada.

Plano canônico:
[commercial-simulation-plan.md](../demo/commercial-simulation-plan.md).
Runbook da reunião:
[meeting-runbook.md](../demo/meeting-runbook.md).
