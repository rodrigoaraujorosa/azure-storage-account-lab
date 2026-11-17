#!/usr/bin/env bash
# 2. Contas de armazenamento: a de upload (privada, sem shared key) e a do frontend (static website).
source "$(dirname "$0")/config.sh"

log "Conta do frontend $ST_WEB (static website)"
az storage account create -g "$RG" -n "$ST_WEB" -l "$AZURE_LOCATION" \
  --sku Standard_LRS --kind StorageV2 \
  --min-tls-version TLS1_2 --https-only true --allow-blob-public-access false \
  --tags "$TAGS" -o none
az storage blob service-properties update --account-name "$ST_WEB" --auth-mode key --only-show-errors \
  --static-website --index-document index.html --404-document index.html -o none
WEB_ORIGIN="$(web_origin)"
echo "Frontend: $WEB_ORIGIN"

log "Conta de upload $ST_UPLOAD (sem acesso público e sem shared key)"
az storage account create -g "$RG" -n "$ST_UPLOAD" -l "$AZURE_LOCATION" \
  --sku Standard_LRS --kind StorageV2 --access-tier Hot \
  --min-tls-version TLS1_2 --https-only true \
  --allow-blob-public-access false --allow-shared-key-access false \
  --tags "$TAGS" -o none
UPLOAD_ID="$(az storage account show -g "$RG" -n "$ST_UPLOAD" --query id -o tsv)"

log "Contêiner $UPLOAD_CONTAINER (pelo plano de controle, sem precisar de chave)"
az storage container-rm create -g "$RG" --storage-account "$ST_UPLOAD" \
  --name "$UPLOAD_CONTAINER" --public-access off -o none

log "Blob service: CORS para o frontend e soft delete de 7 dias"
# CORS e soft delete pelo ARM: com shared key desabilitada, `az storage cors` (plano de dados) não funciona.
jq -n --arg web "$WEB_ORIGIN" --arg local "$LOCAL_ORIGIN" '{
  properties: {
    cors: { corsRules: [{
      allowedOrigins: [$web, $local],
      allowedMethods: ["PUT", "OPTIONS"],
      allowedHeaders: ["*"],
      exposedHeaders: ["*"],
      maxAgeInSeconds: 3600
    }]},
    deleteRetentionPolicy: { enabled: true, days: 7 },
    containerDeleteRetentionPolicy: { enabled: true, days: 7 }
  }
}' >"$ROOT/.blob-service.json"
az rest --method put \
  --url "https://management.azure.com${UPLOAD_ID}/blobServices/default?api-version=2023-05-01" \
  --body @"$(az_path "$ROOT/.blob-service.json")" -o none
rm -f "$ROOT/.blob-service.json"

# Opcional: você mesmo com acesso aos dados, para listar e baixar os uploads com --auth-mode login.
if [[ "${ASSIGN_DATA_ROLE_TO_ME:-true}" == "true" ]]; then
  if ME="$(az ad signed-in-user show --query id -o tsv 2>/dev/null)"; then
    log "Storage Blob Data Contributor para você no contêiner $UPLOAD_CONTAINER"
    az role assignment create --assignee-object-id "$ME" --assignee-principal-type User \
      --role "Storage Blob Data Contributor" \
      --scope "$UPLOAD_ID/blobServices/default/containers/$UPLOAD_CONTAINER" -o none
  else
    warn "Não deu para identificar o usuário logado; pulei a atribuição de papel para você."
  fi
fi

log "Pronto."
