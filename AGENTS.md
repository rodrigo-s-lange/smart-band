# Orientacoes para agentes

- Preserve a separacao entre edge, cloud, frontend, sync, contratos e dispositivos.
- O edge local e a autoridade transacional; a cloud nao autoriza consumo em tempo real.
- Toda operacao de debito precisa ser atomica e idempotente.
- Nenhuma dependencia do laboratorio i5 pode entrar no produto.
- Segredos, tokens, senhas e arquivos `.env` reais nunca entram no repositorio.
- Contratos devem ser definidos antes das implementacoes que os consomem.
- Simuladores precedem hardware e firmware ESP32.
- Mudancas arquiteturais relevantes devem ser registradas tambem no vault.
