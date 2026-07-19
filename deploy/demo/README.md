# Deploy da demonstração

Este compose publica somente o Streamlit. SQLite fica em volume Docker e não há
banco ou Edge API expostos.

## Iniciar

1. copie `.env.example` para um arquivo `.env` local não versionado;
2. gere uma senha temporária forte;
3. mantenha `SMARTBAND_DEMO_BIND_ADDRESS=127.0.0.1` para proxy/túnel local;
4. execute `docker compose up -d --build`;
5. valide `http://127.0.0.1:8501/_stcore/health`;
6. acesse e execute o reset em Controle da Demo.

Para contingência LAN, configure temporariamente o endereço privado do host em
`SMARTBAND_DEMO_BIND_ADDRESS`. Não use `0.0.0.0` sem revisar firewall e rotas.

## Parar e remover o acesso

```bash
sudo systemctl stop cloudflared-smartband-demo
docker compose down
```

Para reabrir o acesso temporário após validar o container:

```bash
sudo systemctl start cloudflared-smartband-demo
```

O serviço de túnel da demo é separado do túnel dos demais produtos. Sua
configuração e credencial ficam fora do repositório. Parar esse serviço remove o
acesso público sem afetar a aplicação local nem os outros hostnames.

O volume é preservado. Para restaurar o cenário, prefira o reset na aplicação.
Remover o volume apaga somente dados fictícios, mas deve ser uma ação explícita.

## Publicação externa

O domínio pretendido é `https://pulseira.easysmart.com.br`. O túnel/proxy deve:

- encaminhar apenas para `http://127.0.0.1:8501`;
- terminar TLS;
- não desativar a senha da aplicação;
- não publicar SSH, Docker, SQLite ou Edge API;
- permitir desligamento imediato após a reunião.

Credenciais e configuração do provedor permanecem fora do Git.
