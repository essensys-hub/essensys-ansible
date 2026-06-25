#!/usr/bin/env bash
# Charge un fichier YAML SOPS déchiffré en variables d'environnement (clés → UPPER_SNAKE).
# Usage: eval "$(scripts/lib/sops-load-env.sh secrets/operator/backup.syno.sops.yaml)"
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: sops-load-env.sh <file.sops.yaml>" >&2
  exit 1
fi

FILE="$1"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
[[ "$FILE" != /* ]] && FILE="$ROOT/$FILE"

if [[ ! -f "$FILE" ]]; then
  echo "Missing SOPS file: $FILE" >&2
  exit 1
fi

export SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-$ROOT/.age/keys.txt}"

if ! command -v sops >/dev/null 2>&1; then
  echo "sops not installed (brew install sops)" >&2
  exit 1
fi

while IFS= read -r line; do
  [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
  [[ "$line" =~ ^[a-z][a-z0-9_]*: ]] || continue
  key="${line%%:*}"
  val="${line#*: }"
  val="${val#\"}"; val="${val%\"}"
  val="${val#\'}"; val="${val%\'}"
  upper="$(echo "$key" | tr '[:lower:]' '[:upper:]')"
  printf 'export %s=%q\n' "$upper" "$val"
done < <(sops -d "$FILE")
