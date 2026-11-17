#!/usr/bin/env bash
# Gera o environment do Postman com os endereços reais do lab (depois do deploy).
# Importe no Postman: postman/azure-storage-account-lab.postman_environment.json
source "$(dirname "$0")/config.sh"

OUT="$ROOT/postman/azure-storage-account-lab.postman_environment.json"
GATEWAY="$(az apim show -g "$RG" -n "$APIM" --query gatewayUrl -o tsv)"
FUNC_HOST="$(func_host)"

jq -n \
  --arg apim "$GATEWAY/$APIM_API_PATH" \
  --arg origin "$(web_origin)" \
  --arg storage "$ST_UPLOAD" \
  --arg func "$FUNC_HOST" \
  --arg max "$MAX_UPLOAD_MB" '{
  name: "azure-storage-account-lab",
  values: [
    {key: "apimBaseUrl",    value: $apim,    enabled: true},
    {key: "frontendOrigin", value: $origin,  enabled: true},
    {key: "storageAccount", value: $storage, enabled: true},
    {key: "functionHost",   value: $func,    enabled: true},
    {key: "maxUploadMb",    value: $max,     enabled: true}
  ],
  _postman_variable_scope: "environment"
}' >"$OUT"

log "Gerado: $OUT"
echo "No Postman: Import → este arquivo e postman/azure-storage-account-lab.postman_collection.json"
