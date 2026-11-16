<p align="center">
  <img src="https://img.shields.io/badge/status-experimental-C8962E?style=flat-square" alt="Status: experimental">
  <a href="LICENSE"><img src="https://img.shields.io/github/license/rodrigoaraujorosa/azure-storage-account-lab?style=flat-square&color=1E5C48&label=licen%C3%A7a" alt="Licença: MIT"></a>
  <img src="https://img.shields.io/badge/Azure-Storage%20Account-1E5C48?style=flat-square&logo=microsoftazure&logoColor=white" alt="Azure Storage Account">
  <img src="https://img.shields.io/badge/tipo-lab-1E5C48?style=flat-square" alt="Tipo: lab">
  <a href="https://www.conventionalcommits.org/pt-br/v1.0.0/"><img src="https://img.shields.io/badge/commits-conventional-C8962E?style=flat-square" alt="Conventional Commits"></a>
</p>

# Azure Storage Account — lab

Lab para validar na prática a arquitetura de um Azure Storage Account: upload, acesso por SAS, eventos e ciclo de vida dos dados.

## 🎯 O que validar

- [ ] Upload de arquivos para Blob Storage (pequenos e grandes, em blocos).
- [ ] Acesso delegado com SAS (service SAS e user delegation SAS) e expiração.
- [ ] Eventos de blob criados/apagados com Event Grid.
- [ ] Políticas de ciclo de vida (hot → cool → archive → exclusão).
- [ ] Redundância, soft delete e versionamento.

## 🏗️ Arquitetura

> A definir. O desenho fica em `docs/assets/` e a infraestrutura em `infra/`.

Todos os recursos ficam no resource group `rg-azure-storage-account-lab`, com a tag `repo=azure-storage-account-lab`.

## 🚀 Como rodar

**Pré-requisitos:** assinatura Azure e [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) autenticada (`az login`).

```bash
cp .env.example .env   # ajuste as variáveis
source .env

az group create \
  --name "$RESOURCE_GROUP" \
  --location "$AZURE_LOCATION" \
  --tags repo=azure-storage-account-lab
```

## ✅ Resultado

> A preencher ao final do lab: o que funcionou, o que não funcionou e o que ficou de aprendizado.

## 💸 Custos e limpeza

> Custo total: a registrar.

Para apagar tudo:

```bash
az group delete --name rg-azure-storage-account-lab --yes --no-wait
```

## 📄 Licença

[MIT](LICENSE) © Rodrigo de Araujo Rosa
