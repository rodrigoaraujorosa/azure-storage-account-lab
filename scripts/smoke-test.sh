#!/usr/bin/env bash
# Teste rápido pelo terminal, sem navegador: pede a SAS ao APIM, envia 1 MiB direto ao Storage
# e confere que a SAS não serve para ler e que o limite de tamanho é respeitado.
source "$(dirname "$0")/config.sh"

command -v curl >/dev/null || { echo "Ferramenta ausente: curl" >&2; exit 1; }
API="$(az apim show -g "$RG" -n "$APIM" --query gatewayUrl -o tsv)/$APIM_API_PATH/sas"
TMP="$(mktemp -d)"
trap 'cd "$ROOT" && rm -rf "$TMP"' EXIT
# Caminhos relativos: o curl do Git Bash é um executável Windows e não entende /tmp/...
cd "$TMP"
pass() { printf '  \033[32mOK\033[0m   %s\n' "$*"; }
fail() { printf '  \033[31mFALHA\033[0m %s\n' "$*"; FAILED=1; }
FAILED=0

log "1. Pedido de SAS pelo APIM"
head -c 1048576 /dev/urandom >smoke.bin
CODE="$(curl -sS -o sas.json -w '%{http_code}' -X POST "$API" \
  -H 'Content-Type: application/json' \
  -d '{"fileName":"smoke.bin","size":1048576,"contentType":"application/octet-stream"}')"
if [[ "$CODE" == "201" ]]; then pass "SAS emitida ($CODE)"; else fail "esperava 201, veio $CODE: $(cat sas.json)"; exit 1; fi
URL="$(jq -r .uploadUrl sas.json)"
echo "  blob: $(jq -r .blobName sas.json)  expira: $(jq -r .expiresOn sas.json)"

log "2. Upload direto ao Storage (Put Blob)"
CODE="$(curl -sS -o resposta.tmp -w '%{http_code}' -X PUT "$URL" \
  -H 'x-ms-blob-type: BlockBlob' -H 'Content-Type: application/octet-stream' --data-binary @smoke.bin)"
[[ "$CODE" == "201" ]] && pass "upload aceito ($CODE)" || fail "upload: esperava 201, veio $CODE"

log "3. A mesma SAS não pode ler o blob"
CODE="$(curl -sS -o resposta.tmp -w '%{http_code}' "$URL")"
[[ "$CODE" == "403" ]] && pass "leitura negada ($CODE)" || fail "leitura: esperava 403, veio $CODE"

log "4. Arquivo acima do limite é recusado pelo microserviço"
BIG=$(( (MAX_UPLOAD_MB + 1) * 1024 * 1024 ))
CODE="$(curl -sS -o resposta.tmp -w '%{http_code}' -X POST "$API" \
  -H 'Content-Type: application/json' -d "{\"fileName\":\"big.bin\",\"size\":$BIG}")"
[[ "$CODE" == "400" ]] && pass "limite respeitado ($CODE)" || fail "limite: esperava 400, veio $CODE"

log "5. Acesso com shared key está desabilitado na conta de upload"
KEY_ALLOWED="$(az storage account show -g "$RG" -n "$ST_UPLOAD" --query allowSharedKeyAccess -o tsv)"
[[ "$KEY_ALLOWED" == "false" ]] && pass "allowSharedKeyAccess=false" || fail "allowSharedKeyAccess=$KEY_ALLOWED"

exit "$FAILED"
