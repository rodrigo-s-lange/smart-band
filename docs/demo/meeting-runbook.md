# Runbook da reunião comercial

Status: **publicação externa encerrada** — 2026-07-24. O roteiro permanece
reutilizável, mas exige nova autorização e novo provisionamento antes de outra
reunião.

Este runbook conclui a parte documental da D7. Ele orienta a apresentação da
simulação Smart-Band sem transformar fixtures em decisões comerciais.

## Resultado esperado

Em até 15 minutos, a VRPlay deve compreender:

- como cadastro, crédito, pulseira, gateway e atração formam uma operação única;
- como confirmação na pulseira reduz liberações incorretas;
- como o sistema ajuda a vender, operar e auditar créditos;
- quais decisões ainda precisam ser aprovadas pela VRPlay.

## Roteiro comercial — 12 minutos

| Tempo | Tela/ação | Mensagem principal |
| --- | --- | --- |
| 00:00–01:00 | Abertura | “Vamos acompanhar uma pessoa desde o caixa até a atração e o encerramento da sessão.” |
| 01:00–02:30 | Visão Geral | Mostrar vendas, utilização e estado operacional como uma fonte comum de informação. |
| 02:30–04:00 | Atendimento | Cadastrar João Demo, vincular a pulseira e carregar cinco créditos fictícios. Explicar conciliação sem afirmar integração real com adquirente ou Pix. |
| 04:00–07:00 | Pulseira e gateway | Executar dois cliques, selecionar o código no gateway, mostrar `CORRIDA / -1 OK?`, confirmar e liberar. Destacar que o código seleciona; a pessoa confirma. |
| 07:00–08:00 | Sessão | Mostrar `LIBERADO`, saldo 4 e cronômetro de cinco minutos. Explicar que duração e preço são parâmetros da apresentação. |
| 08:00–09:00 | Encerramento | Solicitar `ENCERRAR SESSAO?` e fechar no gateway. Explicar que somente essa ação libera a pulseira e fecha a métrica de uso, com ou sem cronômetro. |
| 09:00–10:30 | Gestão | Mostrar Dispositivos, Alertas e timeline. Citar tamper, acessibilidade e ocupação BLE como decisões/propostas, não como funcionalidades contratadas. |
| 10:30–12:00 | Fechamento | Apresentar ganhos esperados e abrir o documento de decisões do cliente. Pedir validação do fluxo antes de discutir hardware. |

Na demonstração, abrir a página **Decisões** para conduzir as 34 perguntas
numeradas. Registrar as respostas posteriormente no documento oficial; não
editar regras da aplicação durante a reunião.

Meta interna: fluxo operacional principal em até 5 minutos. Se a conversa se
estender, preservar o fluxo principal e cortar telas auxiliares.

Se perguntarem sobre falha do gateway: outro gateway do site pode fechar o uso.
Como último recurso, uma nova atividade fecha a participação anterior daquela
pulseira e identifica a duração como estimada; grupos continuam ativos.

## Fala de abertura

> A proposta não é apenas trocar uma ficha por uma pulseira. É ligar venda,
> experiência, liberação e auditoria em um único fluxo local, simples para o
> visitante e controlável para a VRPlay.

## Fala de fechamento

> A direção técnica já está definida. Para transformar esta experiência em
> produto, precisamos agora validar com a VRPlay preço, duração, capacidade,
> acionamento físico, dados cadastrais e regras operacionais de cada atração.

## Roteiro técnico opcional — 5 minutos

Usar somente se houver interesse técnico ou pergunta específica:

1. appliance local-first como autoridade de operação, saldo e ledger;
2. gateways cadastrados por atração e fila compartilhada;
3. BLE para descoberta e GATT para confirmação/resultado;
4. código visual como seletor, nunca como autorização isolada;
5. operação local independente da internet e serviços externos opcionais;
6. PostgreSQL, contratos e simuladores antes de hardware e firmware.

Não apresentar a simulação Streamlit como frontend definitivo nem afirmar que
fixtures de preço, duração, pagamento, tamper ou acionamento já foram aprovadas.

## Preparação do cenário

O domínio e o tunnel citados abaixo estão desativados. Não executar este roteiro
sem reprovisionar o acesso conforme `deploy/demo/README.md` e repetir o gate D6.

1. abrir `https://pulseira.easysmart.com.br` e autenticar;
2. abrir **Controle da Demo** e restaurar a fixture;
3. confirmar `CORRIDA / LIVRE` e ausência de pulseira vinculada;
4. manter abertas somente as abas necessárias;
5. usar zoom de 100% e modo tela cheia na TV;
6. silenciar notificações do sistema operacional;
7. não deixar senha, terminal, painel Cloudflare ou arquivos internos visíveis.

## Contingência

| Falha | Ação imediata | Limite |
| --- | --- | --- |
| Wi-Fi do local falhou | Conectar o notebook ao hotspot do celular e recarregar o domínio. | 2 minutos |
| Internet do i5/túnel falhou | Usar o vídeo local e as capturas; continuar a narrativa sem diagnosticar ao vivo. | 1 minuto |
| Aplicação abriu com estado residual | Controle da Demo → Restaurar fixture. | 10 segundos |
| Senha recusada | Conferir layout do teclado e digitar novamente; não exibir a senha na TV. | 30 segundos |
| TV/resolução inadequada | Duplicar tela, 1920×1080, zoom de 100%; se necessário apresentar no notebook. | 2 minutos |
| Erro inesperado no fluxo | Restaurar fixture uma vez. Se repetir, usar vídeo/capturas e seguir para decisões. | 1 tentativa |

O objetivo da reunião é vender e validar a direção. Não gastar a janela da VRPlay
fazendo diagnóstico técnico.

## Checklist — dia anterior

- [ ] domínio responde por HTTPS e exige senha;
- [ ] senha válida entra e senha inválida é recusada;
- [ ] container saudável, túnel ativo e porta ligada somente em loopback;
- [ ] fixture restaura em até 10 segundos;
- [ ] três ensaios cronometrados registrados;
- [ ] outro notebook testado;
- [ ] acesso por rede móvel testado;
- [ ] TV/resolução e cabo/adaptador testados;
- [ ] vídeo e capturas salvos localmente no notebook;
- [ ] carregadores, hotspot e modo “não perturbe” preparados;
- [ ] documento de decisões do cliente disponível offline.

## Checklist — dia da reunião

- [ ] conferir saúde do domínio e horário do i5;
- [ ] testar login sem projetar a senha;
- [ ] executar um smoke curto e restaurar a fixture;
- [ ] confirmar `CORRIDA / LIVRE` antes de compartilhar a tela;
- [ ] deixar hotspot desligado, mas pronto;
- [ ] confirmar vídeo local reproduzível sem internet;
- [ ] apresentar S1 e no máximo dois diferenciais;
- [ ] anotar decisões sem editar regras da demo ao vivo;
- [ ] restaurar a fixture ao terminar;
- [ ] encerrar o acesso público após a janela autorizada.

## Registro dos ensaios

Cada ensaio deve registrar data/hora, duração, resultado, saldo final, retorno a
`LIVRE` e reset sem resíduo. Provas físicas de notebook, rede móvel e TV devem
registrar dispositivo/rede utilizados, sem armazenar senha ou dado pessoal.
