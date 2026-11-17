# CLAUDE.md

Lab da trilha de labs e estudos do Ogma (`docs/labs.md`), na conta pessoal `rodrigoaraujorosa`. Sem codinome.

## Cenário

Upload de 100–400 MB pelo navegador direto no Blob Storage. O frontend pede a SAS por Frontend → APIM → Function; o arquivo vai Frontend → Storage, nunca pelo APIM.

## Convenções

- Conteúdo e README em pt-BR; código, nomes de recursos e IDs em inglês.
- Infraestrutura **só com Azure CLI** em `scripts/` (Bicep/Terraform ficam para outro lab). Cada etapa `NN-*.sh` faz `source scripts/config.sh` e deve poder rodar de novo sem quebrar.
- Todo recurso fica no resource group `rg-azure-storage-account-lab`, com a tag `repo=azure-storage-account-lab`. Os nomes vêm de `scripts/config.sh`.
- Toda mudança de infraestrutura nos scripts tem o passo equivalente em `docs/portal.md`.
- A conta de upload fica sem shared key: use o plano de controle (`az storage container-rm`, `az rest` em `blobServices`) ou `--auth-mode login`.
- Nunca registre em log a URL com a SAS.
- Microserviço em `src/sas_service/` (Functions Python v2). As regras puras ficam em `sas_logic.py`, com testes em `tests/unit/`.
- Antes de commitar: `uv run --group dev ruff check . && uv run --group dev ruff format --check . && uv run --group dev pytest`.
- Commits em Conventional Commits (`feat(web): ...`, `fix(scripts): ...`).
- Ao terminar: preencher "Resultado" e "Custos e limpeza" no README, rodar `scripts/cleanup.sh`, trocar o topic para `archived` e arquivar o repo.
