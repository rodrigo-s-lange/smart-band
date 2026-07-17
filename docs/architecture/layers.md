# Camadas e responsabilidades

## Pulseira

Cria a solicitação efêmera, exibe o código, confirma atração e custo e produz
provas autenticadas. Não mantém saldo autoritativo.

## Gateway

Escaneia BLE, reporta sightings, exibe a fila no TFT e transporta a sessão GATT.
Pode atuar como gateway operador, gateway de rádio ou ambos.

## Appliance local

Mantém fila global, identidade, regras, ledger, saldo, aplicação e banco. É a
única autoridade transacional e funciona sem internet.

## Serviços externos opcionais

Licença, atualização, suporte, monitoramento técnico e backup autorizado. Não
fazem parte do caminho crítico nem recebem dados pessoais por padrão.

## Contratos

OpenAPI, eventos e protocolo BLE são fronteiras versionadas. Domínio não depende
de ESP-IDF, framework web ou transporte específico.

## Implantação

O i5 é laboratório. A appliance comercial precisa ser instalável em outro host
Linux sem mudanças de código ou estado oculto.
