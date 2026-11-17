#!/usr/bin/env bash
# 3. Microserviço de SAS: Function App (Flex Consumption, Python) com managed identity.
source "$(dirname "$0")/config.sh"

log "Conferindo se $FUNC_LOCATION aceita Flex Consumption"
if ! az functionapp list-flexconsumption-locations --query "[].name" -o tsv | tr -d '\r' | grep -qx "$FUNC_LOCATION"; then
  echo "A região '$FUNC_LOCATION' não tem Flex Consumption. Defina FUNC_LOCATION no .env com uma destas:" >&2
  az functionapp list-flexconsumption-locations --query "[].name" -o tsv >&2
  exit 1
fi

log "Conta interna da Function $ST_FUNC"
az storage account create -g "$RG" -n "$ST_FUNC" -l "$FUNC_LOCATION" \
  --sku Standard_LRS --kind StorageV2 --min-tls-version TLS1_2 --allow-blob-public-access false \
  --tags "$TAGS" -o none

if ! az functionapp show -g "$RG" -n "$FUNC_APP" -o none 2>/dev/null; then
  log "Function App $FUNC_APP (Flex Consumption, Python 3.12)"
  az functionapp create -g "$RG" -n "$FUNC_APP" \
    --storage-account "$ST_FUNC" --flexconsumption-location "$FUNC_LOCATION" \
    --runtime python --runtime-version 3.12 \
    --tags "$TAGS" -o none
fi

log "Managed identity da Function"
PRINCIPAL_ID="$(az functionapp identity assign -g "$RG" -n "$FUNC_APP" --query principalId -o tsv)"
UPLOAD_ID="$(az storage account show -g "$RG" -n "$ST_UPLOAD" --query id -o tsv)"

log "Papéis mínimos para emitir user delegation SAS"
# Gerar a user delegation key é uma ação da conta: o papel precisa estar no escopo da conta.
az role assignment create --assignee-object-id "$PRINCIPAL_ID" --assignee-principal-type ServicePrincipal \
  --role "Storage Blob Delegator" --scope "$UPLOAD_ID" -o none
# A SAS só concede o que a identidade pode fazer: escrita, e só neste contêiner.
az role assignment create --assignee-object-id "$PRINCIPAL_ID" --assignee-principal-type ServicePrincipal \
  --role "Storage Blob Data Contributor" \
  --scope "$UPLOAD_ID/blobServices/default/containers/$UPLOAD_CONTAINER" -o none

log "Configurações da aplicação"
az functionapp config appsettings set -g "$RG" -n "$FUNC_APP" -o none --settings \
  "STORAGE_ACCOUNT_URL=https://$ST_UPLOAD.blob.core.windows.net" \
  "UPLOAD_CONTAINER=$UPLOAD_CONTAINER" \
  "SAS_TTL_MINUTES=$SAS_TTL_MINUTES" \
  "MAX_UPLOAD_MB=$MAX_UPLOAD_MB"

command -v zip >/dev/null || { echo "Ferramenta ausente: zip" >&2; exit 1; }
log "Publicando o código (zip deploy com build remoto)"
ZIP="$ROOT/.sas_service.zip"
rm -f "$ZIP"
(cd "$ROOT/src/sas_service" && zip -qr "$(az_path "$ZIP")" . -x '__pycache__/*' '*/__pycache__/*' 'local.settings*.json' '.funcignore')
az functionapp deployment source config-zip -g "$RG" -n "$FUNC_APP" --src "$(az_path "$ZIP")" --build-remote true -o none
rm -f "$ZIP"

log "Pronto. Host: $(func_host)"
echo "Os papéis podem levar alguns minutos para valer. Se a SAS falhar com 403 logo no início, espere e tente de novo."
