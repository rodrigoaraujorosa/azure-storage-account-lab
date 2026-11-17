#!/usr/bin/env bash
# 1. Resource providers e resource group do lab. Apagar este grupo apaga o lab inteiro.
source "$(dirname "$0")/config.sh"

# Assinatura nova (ex.: Azure for Students) vem sem os providers registrados.
for provider in Microsoft.Storage Microsoft.Web Microsoft.ApiManagement \
  Microsoft.Insights Microsoft.OperationalInsights; do
  state="$(az provider show -n "$provider" --query registrationState -o tsv)"
  if [[ "$state" != "Registered" ]]; then
    log "Registrando o provider $provider (só na primeira vez; leva alguns minutos)"
    az provider register -n "$provider" --wait -o none
  fi
done

log "Resource group $RG em $AZURE_LOCATION"
az group create --name "$RG" --location "$AZURE_LOCATION" --tags "$TAGS" -o none

log "Pronto. Sufixo dos nomes: $SUFFIX"
