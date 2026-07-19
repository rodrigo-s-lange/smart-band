# ADR 0013 — Tamper Detection & Child Safety

- Status: proposta
- Data: 2026-07-19

## Contexto

Detectar pulseira aberta ou removida pode apoiar a equipe e responsáveis por
menores. O advertising BLE v1 não carrega esse estado. Alterá-lo silenciosamente
quebraria vetores, simuladores e futuros consumidores.

## Decisão proposta

Preservar o v1 e reservar uma extensão v2 autenticada com `tamper_status`, sem
identificador permanente. A semântica distingue `secure`, `removal_detected`,
`sensor_fault` e `unknown`; detalhe e contador monotônico podem ser confirmados
por GATT. O contrato está em
[contracts/proximity/tamper-status.md](../../contracts/proximity/tamper-status.md).

O recurso é uma camada de detecção e resposta. Não é garantia de localização,
permanência da criança, ausência de violação ou atuação humana. Sensor, alerta
proativo, destinatários, prazo e inclusão no MVP dependem da decisão D14 da
VRPlay e de ensaio físico.

## Consequências

- nenhum byte do advertising v1 muda;
- implementação v2 exige novos vetores, eventos, simuladores e critérios de
  falsos positivos/negativos;
- falha ou estado desconhecido do sensor nunca equivale a `secure`;
- anúncio contínuo precisa de decisão própria sobre bateria, privacidade e
  rotação de identificadores;
- esta ADR proposta não autoriza hardware ou firmware.
