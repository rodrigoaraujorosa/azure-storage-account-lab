#!/usr/bin/env bash
# Configuração comum aos scripts. Não execute direto: os outros scripts fazem `source` dele.
set -euo pipefail

# Git Bash no Windows converte "/subscriptions/..." em caminho de arquivo; isto desliga a conversão.
export MSYS_NO_PATHCONV=1

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT/.env"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Crie o arquivo .env a partir de .env.example (cp .env.example .env) e preencha." >&2
  exit 1
fi
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

for tool in az jq; do
  command -v "$tool" >/dev/null || { echo "Ferramenta ausente: $tool" >&2; exit 1; }
done

# No Git Bash do Windows, a saída do az vem com \r no fim das linhas e estraga as variáveis.
case "$(uname -s)" in
  MINGW* | MSYS* | CYGWIN*) az() { command az "$@" | tr -d '\r'; } ;;
esac

# Sufixo aleatório para os nomes globais (Storage, Function, APIM). Gerado uma vez e salvo no .env.
if [[ -z "${SUFFIX:-}" ]]; then
  SUFFIX="$(LC_ALL=C tr -dc 'a-z0-9' </dev/urandom | head -c 6 || true)"
  printf '\nSUFFIX=%s\n' "$SUFFIX" >>"$ENV_FILE"
fi

REPO="azure-storage-account-lab"
TAGS="repo=$REPO"

AZURE_LOCATION="${AZURE_LOCATION:-brazilsouth}"
FUNC_LOCATION="${FUNC_LOCATION:-$AZURE_LOCATION}"
APIM_LOCATION="${APIM_LOCATION:-$AZURE_LOCATION}"

RG="${RESOURCE_GROUP:-rg-$REPO}"
# Contas de armazenamento: 3-24 letras minúsculas e números, sem hífen. "stasal" = st + azure-storage-account-lab.
ST_UPLOAD="stasalup$SUFFIX"   # recebe os arquivos (privada, sem shared key)
ST_WEB="stasalweb$SUFFIX"     # hospeda o frontend (static website)
ST_FUNC="stasalfn$SUFFIX"     # storage interno da Function App
FUNC_APP="func-$REPO-$SUFFIX"
APIM="apim-$REPO-$SUFFIX"

UPLOAD_CONTAINER="${UPLOAD_CONTAINER:-uploads}"
SAS_TTL_MINUTES="${SAS_TTL_MINUTES:-15}"
MAX_UPLOAD_MB="${MAX_UPLOAD_MB:-400}"
LOCAL_ORIGIN="${LOCAL_ORIGIN:-http://localhost:8080}"

APIM_API_ID="upload-sas"
APIM_API_PATH="uploads"
APIM_NV_FUNCTION_KEY="sas-function-key"

if [[ -n "${AZURE_SUBSCRIPTION_ID:-}" ]]; then
  az account set --subscription "$AZURE_SUBSCRIPTION_ID"
fi
SUBSCRIPTION_ID="$(az account show --query id -o tsv)"

# Host da Function (ex.: func-...azurewebsites.net). Lido do recurso ARM: o formato de
# `az functionapp show` muda entre versões do CLI e, no Flex Consumption, pode vir vazio.
func_host() {
  az resource show -g "$RG" -n "$FUNC_APP" --resource-type Microsoft.Web/sites \
    --query properties.defaultHostName -o tsv
}

# Caminho de arquivo para o az: no Git Bash ele é Python para Windows e não entende /c/...
az_path() { if command -v cygpath >/dev/null; then cygpath -w "$1"; else printf '%s' "$1"; fi; }

log() { printf '\n\033[1;32m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[aviso] %s\033[0m\n' "$*" >&2; }

# Origem do frontend publicado (https://<conta>.z<N>.web.core.windows.net, sem barra no fim).
web_origin() {
  az storage account show -g "$RG" -n "$ST_WEB" --query primaryEndpoints.web -o tsv | sed 's:/*$::'
}
