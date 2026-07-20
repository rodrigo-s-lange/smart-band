# Smart-Band Commercial Demo

Simulação comercial isolada em Streamlit. Não é o frontend operacional, não usa
dados reais e não define regras comerciais do produto.

## Executar localmente

```bash
python -m venv .venv
.venv/bin/python -m pip install -r requirements-dev.txt
SMARTBAND_DEMO_ALLOW_NO_AUTH=true .venv/bin/streamlit run app.py
```

No PowerShell:

```powershell
python -m venv .venv
.venv\Scripts\python -m pip install -r requirements-dev.txt
$env:SMARTBAND_DEMO_ALLOW_NO_AUTH="true"
.venv\Scripts\streamlit run app.py
```

O banco SQLite fica em `data/demo.sqlite3` por padrão. Para testes ou deploy,
use `SMARTBAND_DEMO_DB` com um caminho externo ao código.

## Autenticação

Sem `SMARTBAND_DEMO_ALLOW_NO_AUTH=true`, a aplicação exige
`SMARTBAND_DEMO_PASSWORD`. A senha nunca pode ser versionada. O bypass existe
somente para desenvolvimento local e testes.

## Testar

```bash
python -m pytest tests
```

## Limites

- preço de R$ 20, pacotes e dados cadastrais são fixtures da reunião;
- Corrida, Boxe, Explorador e Tiro consomem 1 crédito apenas na demo;
- pagamento, BLE, vibracall, tamper e acionamento são simulados;
- SQLite não substitui o PostgreSQL autoritativo do produto;
- Streamlit não substitui `apps/operator-web`.

## Displays e tempos da apresentação

- pulseira: OLED azul 128×32, um clique para saldo e dois cliques para acesso;
- gateway: TFT 170×320 vertical, uma atração ativa e até quatro códigos grandes;
- clique duplo: segundo clique entre 30 ms e 2 s;
- código e confirmação: janelas independentes de 30 s;
- sessão: 5 minutos por crédito, sem renovação ou débito automático;
- término: exige confirmação no gateway antes de a atração voltar a `LIVRE` e
  de a pulseira poder solicitar outra atividade, com ou sem cronômetro.

São parâmetros da apresentação e não contratos comerciais do produto.

Plano e gates:
[commercial-simulation-plan.md](../../docs/demo/commercial-simulation-plan.md).
