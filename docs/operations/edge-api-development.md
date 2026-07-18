# Edge API — execução de desenvolvimento

## Pré-requisitos

- Go 1.26.5 ou imagem `golang:1.26.5-alpine`
- PostgreSQL 18 com as migrations aplicadas
- `DATABASE_URL` apontando para o banco local

Não use credenciais reais da instalação em fixtures, comandos ou logs.

## Banco de teste

```bash
python tools/database/validate.py \
  --database-url postgresql://postgres:postgres@localhost:5432/smartband

python tools/database/validate.py \
  --database-url postgresql://postgres:postgres@localhost:5432/smartband \
  --prepare-only
```

## Serviço

```bash
cd apps/edge-api
export DATABASE_URL='postgresql://postgres:postgres@localhost:5432/smartband?sslmode=disable'
go run ./cmd/edge-api
```

Verificações sem autenticação:

```bash
curl --fail http://127.0.0.1:8080/v1/health
curl --fail http://127.0.0.1:8080/v1/ready
```

Endpoints operacionais exigem bearer token de gateway ou cookie `sb_session`.
Os tokens conhecidos em `tests/database/fixture.sql` são apenas para testes e
nunca podem ser usados em uma instalação.

## Diagnóstico

- `health` degradado: verificar `DATABASE_URL`, processo e PostgreSQL
- `ready` indisponível com banco saudável: provisionar `appliance_configuration`
- `401`: reprovisionar o segredo; o banco mantém somente SHA-256
- saída do processo: consultar logs JSON pelo `request_id`

O processo responde a SIGINT/SIGTERM com shutdown gracioso. O banco não deve ter
porta publicada na LAN da operação.
