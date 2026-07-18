# Validação PostgreSQL

O validador aplica todas as seções `goose Up`, executa fixtures e testes de
invariantes, disputa duas reservas concorrentes em conexões diferentes, cobre
ack ambíguo, disputa cancelamento contra despacho e executa todas as seções
`goose Down` em ordem reversa. No modo container ele também reinicia o
PostgreSQL entre a persistência do comando e o ack.

Com PostgreSQL acessível por URL:

```bash
python tools/database/validate.py \
  --database-url postgresql://postgres:postgres@localhost:5432/smartband
```

No laboratório, com o banco em um container chamado `smartband-stage4-db`:

```bash
python tools/database/validate.py --docker-container smartband-stage4-db
```

O parser local só separa as seções para permitir o mesmo teste sem instalar o
binário do goose. Os arquivos permanecem migrations SQL válidas do goose e a
appliance usará o executor versionado no deploy.
