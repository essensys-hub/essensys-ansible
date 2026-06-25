#!/usr/bin/env bash
# Backup Essensys (secrets Ansible/SOPS, clés age) vers Synology via rclone.
# Planification : launchd 02:00 — voir scripts/install-backup-schedule.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ESSENSYS_ROOT="${ESSENSYS_ROOT:-$(cd "$ROOT/.." && pwd)}"
RCLONE_CONFIG="${RCLONE_CONFIG:-$ROOT/config/rclone.conf}"
LOG_DIR="${BACKUP_LOG_DIR:-$HOME/Library/Logs/essensys-backup}"

mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/backup-$(date +%Y%m%d).log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

# Config Synology depuis SOPS (secrets/operator/backup.syno.sops.yaml)
# shellcheck source=/dev/null
source "$ROOT/scripts/load-backup-syno-config.sh"

RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"

if [[ ! -f "$RCLONE_CONFIG" ]]; then
  log "ERROR: $RCLONE_CONFIG absent — lancer: ./scripts/backup-syno-init.sh"
  exit 1
fi

if ! command -v rclone >/dev/null 2>&1; then
  log "ERROR: rclone non installé (brew install rclone)"
  exit 1
fi

if ! ping -c 1 -W 2 "$SYNO_HOST" >/dev/null 2>&1; then
  log "ERROR: Synology $SYNO_HOST injoignable (réseau local / VPN ?)"
  exit 1
fi

HOST_TAG="$(hostname -s 2>/dev/null || echo mac)"
DATE_TAG="$(date +%Y-%m-%d)"
# Remote SMB = racine serveur (tous les partages) : inclure SYNO_SHARE dans le chemin
REMOTE_DEST="${RCLONE_REMOTE}:${SYNO_SHARE}/${BACKUP_REMOTE_BASE}/${HOST_TAG}/daily/${DATE_TAG}"

log "=== Backup Essensys → smb://${SYNO_HOST}/${SYNO_SHARE}/${BACKUP_REMOTE_BASE}/${HOST_TAG}/daily/${DATE_TAG} ==="

STAGING="$(mktemp -d "${TMPDIR:-/tmp}/essensys-backup.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT

mkdir -p "$STAGING/essensys-ansible"

# Secrets & clés (priorité opérateur)
[[ -d "$ROOT/secrets" ]] && cp -a "$ROOT/secrets" "$STAGING/essensys-ansible/"
[[ -d "$ROOT/.age" ]] && cp -a "$ROOT/.age" "$STAGING/essensys-ansible/"
[[ -f "$ROOT/group_vars/essensys/vault.yml" ]] && mkdir -p "$STAGING/essensys-ansible/group_vars/essensys" && cp -a "$ROOT/group_vars/essensys/vault.yml" "$STAGING/essensys-ansible/group_vars/essensys/"
[[ -f "$ROOT/config/.env" ]] && cp -a "$ROOT/config/.env" "$STAGING/essensys-ansible/config.env"

# Chemins supplémentaires (optionnel, séparés par : dans backup.syno.env)
if [[ -n "${BACKUP_EXTRA_PATHS:-}" ]]; then
  IFS=':' read -ra EXTRA <<< "$BACKUP_EXTRA_PATHS"
  for p in "${EXTRA[@]}"; do
    [[ -z "$p" ]] && continue
    if [[ -e "$p" ]]; then
      rel="extra/$(basename "$p")"
      log "  + extra: $p"
      cp -a "$p" "$STAGING/$rel"
    else
      log "  WARN: chemin extra absent: $p"
    fi
  done
fi

# Métadonnées
cat > "$STAGING/BACKUP_INFO.txt" <<EOF
date=$(date -Iseconds)
host=${HOST_TAG}
essensys_root=${ESSENSYS_ROOT}
ansible_root=${ROOT}
user=$(whoami)
EOF

log "Staging: $(du -sh "$STAGING" | awk '{print $1}')"

if ! rclone copy "$STAGING/" "$REMOTE_DEST" \
  --config "$RCLONE_CONFIG" \
  --create-empty-src-dirs \
  --transfers 4 \
  --checkers 8 \
  --log-file "$LOG_FILE" \
  --log-level INFO; then
  log "ERROR: rclone copy a échoué — dernières lignes du log:"
  tail -5 "$LOG_FILE" | while read -r line; do log "  $line"; done
  exit 1
fi

log "OK: copie terminée → $REMOTE_DEST"

# Rétention : supprimer dossiers daily plus vieux que N jours
CUTOFF="$(date -v-${RETENTION_DAYS}d +%Y-%m-%d 2>/dev/null || date -d "-${RETENTION_DAYS} days" +%Y-%m-%d)"
REMOTE_PARENT="${RCLONE_REMOTE}:${SYNO_SHARE}/${BACKUP_REMOTE_BASE}/${HOST_TAG}/daily"

log "Rétention: suppression des snapshots < $CUTOFF (${RETENTION_DAYS} jours)"

rclone lsf "$REMOTE_PARENT/" --config "$RCLONE_CONFIG" --dirs-only 2>/dev/null | while read -r daydir; do
  daydir="${daydir%/}"
  [[ -z "$daydir" ]] && continue
  if [[ "$daydir" < "$CUTOFF" ]]; then
    log "  purge: $daydir"
    rclone purge "${REMOTE_PARENT}/${daydir}" --config "$RCLONE_CONFIG" || log "  WARN: purge $daydir échouée"
  fi
done

log "=== Backup terminé ==="
