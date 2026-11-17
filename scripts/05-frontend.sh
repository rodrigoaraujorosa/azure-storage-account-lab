#!/usr/bin/env bash
# 5. Publica o frontend no static website, já apontando para o APIM.
source "$(dirname "$0")/config.sh"

GATEWAY="$(az apim show -g "$RG" -n "$APIM" --query gatewayUrl -o tsv)"

log "Gerando web/config.js"
cat >"$ROOT/web/config.js" <<EOF
// Gerado por scripts/05-frontend.sh. Não versionar.
window.APP_CONFIG = {
  apiBaseUrl: "$GATEWAY/$APIM_API_PATH",
};
EOF

log "Enviando web/ para o contêiner \$web de $ST_WEB"
az storage blob upload-batch --account-name "$ST_WEB" --auth-mode key --only-show-errors \
  --destination '$web' --source "$(az_path "$ROOT/web")" --overwrite \
  --content-cache-control "no-cache" -o none

log "Pronto. Abra: $(web_origin)"
