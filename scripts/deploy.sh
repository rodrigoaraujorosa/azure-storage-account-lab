#!/usr/bin/env bash
# Sobe o lab inteiro, na ordem. Cada etapa pode ser rodada de novo sozinha.
set -euo pipefail
DIR="$(dirname "$0")"

bash "$DIR/01-resource-group.sh"
bash "$DIR/02-storage.sh"
bash "$DIR/03-function.sh"
bash "$DIR/04-apim.sh"
bash "$DIR/05-frontend.sh"
