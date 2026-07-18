# ADR 0010 — Gateway como identidade operacional

Status: aceita — 2026-07-18

Substitui a exigência de identidade humana individual nas ADRs 0005 e 0009.

## Contexto

Na operação real, qualquer pessoa autorizada pela empresa pode usar um gateway.
Cadastro, login ou PIN individual acrescentariam atrito sem melhorar a decisão
de qual atração pode ser liberada. O equipamento, por outro lado, precisa ser
conhecido, autenticado e associado explicitamente às atrações que controla.

## Decisão

- O gateway cadastrado é a identidade do fluxo operacional.
- Não existe cadastro, seleção, login ou sessão de operador humano para claim,
  cancelamento, acionamento ou reconciliação.
- Cada gateway possui ID, credencial própria, site, estado e relação explícita
  com uma ou mais atrações em `gateway_attractions`.
- O claim exige bearer token do gateway. O corpo contém apenas
  `attraction_id`; `operator_gateway_id` é derivado da credencial e não pode ser
  declarado pelo cliente.
- A appliance valida se o gateway está ativo, pertence ao mesmo site e é
  responsável pela atração solicitada.
- Exceções operacionais registram gateway, ação, motivo e horário, sem
  `operator_id`.
- Ações administrativas locais podem usar uma sessão administrativa genérica,
  mas ela não representa nem identifica quem opera um gateway.

O nome de protocolo `operator_gateway_id` é mantido por compatibilidade e passa
a significar “gateway onde a operação/liberação foi solicitada”. Ele continua
distinto de `radio_gateway_id`.

## Segurança

A credencial é exclusiva por gateway, armazenada somente como hash na
appliance e rotacionável. Um gateway desativado ou retirado perde autorização.
O cadastro gateway ↔ atrações é a fronteira de autorização e precisa de
auditoria administrativa.

## Consequências

A operação fica simples e intercambiável entre pessoas, enquanto a auditoria
permanece vinculada ao equipamento e à atração. Não haverá atribuição pessoal
de uma ação; se futuramente isso se tornar requisito comercial ou regulatório,
será uma decisão nova e não uma suposição no protocolo.
