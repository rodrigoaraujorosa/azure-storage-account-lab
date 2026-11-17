#!/usr/bin/env bash
# Apaga todos os recursos do lab (o resource group inteiro). O repositório fica.
source "$(dirname "$0")/config.sh"

read -r -p "Apagar o resource group $RG e tudo dentro dele? Digite o nome do grupo para confirmar: " ANSWER
[[ "$ANSWER" == "$RG" ]] || { echo "Cancelado."; exit 1; }

log "Apagando $RG"
az group delete --name "$RG" --yes

# O APIM apagado fica em soft delete por 48 h e segura o nome. Purgar libera o nome na hora.
if az apim deletedservice show --service-name "$APIM" --location "$APIM_LOCATION" -o none 2>/dev/null; then
  log "Purgando o APIM $APIM do soft delete"
  az apim deletedservice purge --service-name "$APIM" --location "$APIM_LOCATION"
fi

log "Pronto. Registre no README, em \"Custos e limpeza\", que os recursos foram apagados."
