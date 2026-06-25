#!/usr/bin/env bash
# Bootstrap age + SOPS pour opérateur Essensys (cloud OVH).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KEY_DIR="${SOPS_AGE_KEY_DIR:-$HOME/.config/sops/age}"
KEY_FILE="${SOPS_AGE_KEY_FILE:-$KEY_DIR/keys.txt}"

mkdir -p "$KEY_DIR"

if [[ ! -f "$KEY_FILE" ]]; then
  echo "Génération clé age : $KEY_FILE"
  age-keygen -o "$KEY_FILE"
else
  echo "Clé age existante : $KEY_FILE"
fi

PUBKEY="$(age-keygen -y "$KEY_FILE")"
echo ""
echo "Clé publique age (à ajouter dans .sops.yaml si nouvelle) :"
echo "  $PUBKEY"
echo ""
echo "Export pour édition SOPS :"
echo "  export SOPS_AGE_KEY_FILE=\"$KEY_FILE\""
echo ""
echo "Éditer secrets cloud :"
echo "  cd \"$ROOT\" && sops secrets/cloud/essensys.sops.yaml"
