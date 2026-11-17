#!/usr/bin/env bash
# 1. Resource group do lab. Apagar este grupo apaga o lab inteiro.
source "$(dirname "$0")/config.sh"

log "Resource group $RG em $AZURE_LOCATION"
az group create --name "$RG" --location "$AZURE_LOCATION" --tags "$TAGS" -o none

log "Pronto. Sufixo dos nomes: $SUFFIX"
