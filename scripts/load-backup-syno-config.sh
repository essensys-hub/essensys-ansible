#!/usr/bin/env bash
# Charge la config backup Synology depuis SOPS (source canonique).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOPS_FILE="${BACKUP_SYNO_SOPS_FILE:-$ROOT/secrets/operator/backup.syno.sops.yaml}"

export SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-$ROOT/.age/keys.txt}"

if [[ ! -f "$SOPS_FILE" ]]; then
  echo "Manquant: $SOPS_FILE" >&2
  echo "  cp secrets/operator/backup.syno.sops.yaml.example secrets/operator/backup.syno.sops.yaml" >&2
  echo "  export SOPS_AGE_KEY_FILE=$SOPS_AGE_KEY_FILE" >&2
  echo "  sops --encrypt --in-place secrets/operator/backup.syno.sops.yaml" >&2
  exit 1
fi

eval "$("$ROOT/scripts/lib/sops-load-env.sh" "$SOPS_FILE")"

# Défauts si clés absentes du fichier SOPS (rétrocompat)
export BACKUP_MONOREPO_ROOT="${BACKUP_MONOREPO_ROOT:-/Users/nrineau/ESSENSYS}"
export BACKUP_RCLONE_EXCLUDE_FILE="${BACKUP_RCLONE_EXCLUDE_FILE:-$ROOT/config/backup-rclone-exclude.txt}"
if [[ -n "$BACKUP_RCLONE_EXCLUDE_FILE" && "$BACKUP_RCLONE_EXCLUDE_FILE" != /* ]]; then
  export BACKUP_RCLONE_EXCLUDE_FILE="$ROOT/$BACKUP_RCLONE_EXCLUDE_FILE"
fi

if [[ -z "${SYNO_PASS:-}" || "$SYNO_PASS" == "REPLACE_ME" ]]; then
  echo "Définissez syno_pass dans $SOPS_FILE :" >&2
  echo "  sops $SOPS_FILE" >&2
  exit 1
fi
