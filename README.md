# Smart-Band

Sistema de pulseiras inteligentes para eventos, com consumo de vidas ou
creditos em atracoes, operacao local sem internet e sincronizacao assincrona
com a EasySmart Platform.

## Fontes da verdade

- Vault EasySmart: contexto, decisoes, arquitetura e planejamento.
- Este repositorio: codigo, contratos, migrations, testes e artefatos versionados.
- Ambientes de laboratorio: checkouts reproduziveis, nunca fontes canonicas.

O laboratorio atual fica em `/home/rodrigo/projects/products/smart-band`, mas o
servidor local definitivo sera outro computador. Nenhum componente pode
depender do hostname, IP, caminho ou estado exclusivo desse laboratorio.

## Arquitetura

```text
pulseira <-- IR --> gateway <-- LAN --> edge local
                                        |
                                        `-- MQTT/WSS --> cloud EasySmart
```

O edge local autoriza e grava cada transacao. A cloud recebe as transacoes de
forma assincrona e nao e necessaria para liberar uma atracao.

## Camadas

```text
apps/
  edge-api/             autoridade transacional local
  cloud-api/            consolidacao e operacao remota
  operator-web/         interface operacional offline-first
services/
  edge-sync/            outbox e reconciliacao edge-cloud
contracts/
  openapi/              contratos HTTP
  events/               envelopes e eventos de sincronizacao
  proximity/            protocolo logico pulseira-gateway
simulators/
  band/                 simulador de pulseira
  gateway/              simulador de gateway
deploy/
  edge/                 instalacao portavel do servidor local
  cloud/                integracao isolada com EasySmart Platform
firmware/
  gateway/              reservado para a etapa 11
  band/                 reservado para a etapa 12
hardware/
  gateway/              eletronica e testes do gateway
  band/                 eletronica, energia e mecanica da pulseira
tests/
  e2e/                  cenarios integrados e de falha
docs/
  architecture/         limites e fluxos do sistema
  decisions/            ADRs proximos ao codigo
  operations/           runbooks e procedimentos reproduziveis
```

Leia [docs/architecture/layers.md](docs/architecture/layers.md) e
[docs/architecture/transaction-flow.md](docs/architecture/transaction-flow.md).

## Estado

Descoberta e especificacao. Hardware e firmware ESP32 ficam por ultimo; o
software sera validado primeiro com simuladores.

## Licenca

Nenhuma licenca foi definida ainda.
