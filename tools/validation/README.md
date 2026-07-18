# Validação dos contratos

Executa a mesma suíte usada pela CI:

```bash
python -m pip install -r tools/validation/requirements.txt
python tools/validation/validate.py
```

A suíte verifica:

- JSON Schema 2020-12 e exemplos que devem passar ou falhar
- OpenAPI 3.1
- vetores AES-128-CMAC, domínios e tamanhos de wire payload
- adulteração do custo na transcrição da Decision
- links Markdown locais
- presença das decisões transacionais obrigatórias nos contratos

Não edite valores esperados para fazer uma implementação incorreta passar.
Mudança de wire format ou semântica transacional exige ADR e atualização
coordenada dos contratos, exemplos e vetores.
