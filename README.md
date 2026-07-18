# Smart-Band

Sistema local-first de pulseiras inteligentes para consumo de vidas, créditos e
acessos em atrações de eventos.

## Experiência do MVP

1. A pessoa mantém o botão da pulseira pressionado.
2. A pulseira exibe um código curto e anuncia uma solicitação efêmera por BLE.
3. Gateways próximos reportam a mesma solicitação ao servidor local.
4. O servidor autentica, deduplica e publica o código em uma fila global.
5. O operador da atração seleciona o código verbalizado pela pessoa.
6. A pulseira mostra a atração e o custo e exige confirmação consciente.
7. O servidor reserva o crédito, envia um comando idempotente e grava o
   débito uma única vez somente após confirmar o acionamento da atração.

A confirmação na pulseira é simultaneamente uma regra de segurança e parte da
experiência: a pessoa possui poder real de decisão sobre a ação.

## Arquitetura

```text
pulseiras -- BLE --> gateways -- LAN --> appliance local
    ^                    |                    |
    `------ GATT --------'             API + PostgreSQL
                                        fila + frontend
```

- A appliance local é a autoridade transacional.
- Cada appliance atende um único cliente e um único site operacional por vez.
- Internet e EasySmart Platform não são necessárias para operar.
- Serviços externos são opcionais para licença, atualização, suporte e backup.
- O gateway da atração pode ser diferente do gateway usado como ponte de rádio.

## Camadas do repositório

```text
apps/
  edge-api/                 domínio, fila, ledger e coordenação
  operator-web/             operação local e modo kiosk
services/
  gateway-coordinator/      sightings, claims e sessões de rádio
contracts/
  openapi/                  contratos HTTP e SSE (fila em tempo real)
  events/                   eventos internos versionados
  proximity/                advertising, GATT e confirmação
simulators/
  band/                     pulseira simulada
  gateway/                  gateways e TFTs simulados
deploy/
  appliance/                instalação local reproduzível
firmware/
  band/                     etapa final: firmware da pulseira
  gateway/                  etapa final: firmware do gateway
hardware/
  band/                     energia, display e mecânica
  gateway/                  TFT, rádio e acionamento
tests/
  e2e/                      cenários integrados e de falha
docs/
  architecture/             visão do sistema e fluxos
  decisions/                ADRs
  operations/               runbooks
```

## Fontes da verdade

- Vault EasySmart: decisões, contexto, arquitetura e planejamento.
- Este repositório: código, contratos, migrations, testes, firmware e deploy.
- Servidor i5: laboratório reproduzível, nunca fonte canônica.

## Leitura inicial

1. [AGENTS.md](AGENTS.md)
2. [docs/architecture/layers.md](docs/architecture/layers.md)
3. [docs/architecture/interaction-queue.md](docs/architecture/interaction-queue.md)
4. [docs/architecture/transaction-flow.md](docs/architecture/transaction-flow.md)
5. [docs/architecture/domain-model.md](docs/architecture/domain-model.md)
6. [docs/architecture/domain-invariants.md](docs/architecture/domain-invariants.md)
7. [contracts/proximity/README.md](contracts/proximity/README.md)
8. [docs/decisions/0005-protocol-correction-and-transaction-safety.md](docs/decisions/0005-protocol-correction-and-transaction-safety.md)
9. [docs/decisions/0006-single-tenant-single-site-appliance.md](docs/decisions/0006-single-tenant-single-site-appliance.md)
10. [docs/stage-gates/03-executable-contracts.md](docs/stage-gates/03-executable-contracts.md)
11. [docs/stage-gates/04-postgresql-model.md](docs/stage-gates/04-postgresql-model.md)
12. [docs/roadmap.md](docs/roadmap.md)

## Estado

Etapas 1–4 concluídas: contratos e modelo PostgreSQL estão protegidos por CI. A
próxima frente é a Etapa 5, backend local. Hardware e firmware ESP32 permanecem
no fim.

Validação local:

```bash
python -m pip install -r tools/validation/requirements.txt
python tools/validation/validate.py
```

## Licença

Nenhuma licença foi definida ainda.
