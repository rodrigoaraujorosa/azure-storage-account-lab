#!/usr/bin/env bash
# 4. APIM (Consumption) na frente do microserviço. Só o pedido de SAS passa por aqui, nunca o arquivo.
source "$(dirname "$0")/config.sh"

: "${APIM_PUBLISHER_NAME:?Defina APIM_PUBLISHER_NAME no .env}"
: "${APIM_PUBLISHER_EMAIL:?Defina APIM_PUBLISHER_EMAIL no .env}"

if ! az apim show -g "$RG" -n "$APIM" -o none 2>/dev/null; then
  log "APIM $APIM (Consumption). Leva alguns minutos."
  az apim create -g "$RG" -n "$APIM" -l "$APIM_LOCATION" --sku-name Consumption \
    --publisher-name "$APIM_PUBLISHER_NAME" --publisher-email "$APIM_PUBLISHER_EMAIL" \
    --tags "$TAGS" -o none
fi

log "Function key para o APIM chamar o backend"
FUNC_KEY=""
for _ in $(seq 1 12); do
  FUNC_KEY="$(az functionapp keys list -g "$RG" -n "$FUNC_APP" --query functionKeys.default -o tsv 2>/dev/null || true)"
  [[ -n "$FUNC_KEY" ]] && break
  echo "Aguardando a Function responder..."
  sleep 10
done
[[ -n "$FUNC_KEY" ]] || { echo "Não consegui ler a function key de $FUNC_APP." >&2; exit 1; }

if az apim nv show -g "$RG" --service-name "$APIM" --named-value-id "$APIM_NV_FUNCTION_KEY" -o none 2>/dev/null; then
  az apim nv update -g "$RG" --service-name "$APIM" --named-value-id "$APIM_NV_FUNCTION_KEY" \
    --value "$FUNC_KEY" --secret true -o none
else
  az apim nv create -g "$RG" --service-name "$APIM" --named-value-id "$APIM_NV_FUNCTION_KEY" \
    --display-name "$APIM_NV_FUNCTION_KEY" --value "$FUNC_KEY" --secret true -o none
fi

FUNC_HOST="$(func_host)"
[[ -n "$FUNC_HOST" ]] || { echo "Não consegui ler o host de $FUNC_APP." >&2; exit 1; }

log "API $APIM_API_ID em /$APIM_API_PATH -> https://$FUNC_HOST/api"
# Sem subscription key: ela ficaria exposta no navegador. Ver "Resultado" no README.
az apim api create -g "$RG" --service-name "$APIM" --api-id "$APIM_API_ID" \
  --path "$APIM_API_PATH" --display-name "Upload SAS" --protocols https \
  --service-url "https://$FUNC_HOST/api" --subscription-required false --only-show-errors -o none

az apim api operation create -g "$RG" --service-name "$APIM" --api-id "$APIM_API_ID" \
  --operation-id create-sas --display-name "Gerar SAS de upload" \
  --method POST --url-template "/sas" -o none
# Operação OPTIONS explícita: garante que o preflight do navegador encontre a API e caia na policy de CORS.
az apim api operation create -g "$RG" --service-name "$APIM" --api-id "$APIM_API_ID" \
  --operation-id create-sas-preflight --display-name "Preflight CORS" \
  --method OPTIONS --url-template "/sas" -o none

log "Policy da API (CORS + function key)"
WEB_ORIGIN="$(web_origin)"
sed -e "s#__WEB_ORIGIN__#$WEB_ORIGIN#" -e "s#__LOCAL_ORIGIN__#$LOCAL_ORIGIN#" \
  "$ROOT/infra/apim/upload-sas-policy.xml" |
  jq -Rs '{properties: {format: "rawxml", value: .}}' >"$ROOT/.apim-policy.json"
az rest --method put \
  --url "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RG/providers/Microsoft.ApiManagement/service/$APIM/apis/$APIM_API_ID/policies/policy?api-version=2022-08-01" \
  --body @"$(az_path "$ROOT/.apim-policy.json")" -o none >/dev/null
rm -f "$ROOT/.apim-policy.json"

log "Pronto. Endpoint: $(az apim show -g "$RG" -n "$APIM" --query gatewayUrl -o tsv)/$APIM_API_PATH/sas"
