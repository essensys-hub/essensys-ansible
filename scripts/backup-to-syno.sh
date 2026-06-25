#!/usr/bin/env bash
# Backup monorepo ESSENSYS → Synology via rclone (quotidien 02:00 launchd).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RCLONE_CONFIG="${RCLONE_CONFIG:-$ROOT/config/rclone.conf}"
LOG_DIR="${BACKUP_LOG_DIR:-$HOME/Library/Logs/essensys-backup}"

mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/backup-$(date +%Y%m%d).log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

# shellcheck source=/dev/null
source "$ROOT/scripts/load-backup-syno-config.sh"

RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"
BACKUP_MONOREPO_ROOT="${BACKUP_MONOREPO_ROOT:-/Users/nrineau/ESSENSYS}"
BACKUP_RCLONE_EXCLUDE_FILE="${BACKUP_RCLONE_EXCLUDE_FILE:-$ROOT/config/backup-rclone-exclude.txt}"

if [[ ! -d "$BACKUP_MONOREPO_ROOT" ]]; then
  log "ERROR: monorepo absent: $BACKUP_MONOREPO_ROOT"
  exit 1
fi

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
REMOTE_DEST="${RCLONE_REMOTE}:${SYNO_SHARE}/${BACKUP_REMOTE_BASE}/${HOST_TAG}/daily/${DATE_TAG}"
REMOTE_MONOREPO="${REMOTE_DEST}/ESSENSYS"

log "=== Backup monorepo → smb://${SYNO_HOST}/${SYNO_SHARE}/${BACKUP_REMOTE_BASE}/${HOST_TAG}/daily/${DATE_TAG}/ESSENSYS ==="
log "Source: $BACKUP_MONOREPO_ROOT ($(du -sh "$BACKUP_MONOREPO_ROOT" | awk '{print $1}'))"

RCLONE_ARGS=(
  copy
  "${BACKUP_MONOREPO_ROOT}/"
  "$REMOTE_MONOREPO"
  --config "$RCLONE_CONFIG"
  --create-empty-src-dirs
  --transfers 4
  --checkers 8
  --log-file "$LOG_FILE"
  --log-level INFO
  --stats 30s
  --stats-one-line
)

if [[ -f "$BACKUP_RCLONE_EXCLUDE_FILE" ]]; then
  log "Exclusions: $BACKUP_RCLONE_EXCLUDE_FILE"
  RCLONE_ARGS+=(--exclude-from "$BACKUP_RCLONE_EXCLUDE_FILE")
fi

if ! rclone "${RCLONE_ARGS[@]}"; then
  log "ERROR: rclone copy a échoué — dernières lignes du log:"
  tail -8 "$LOG_FILE" | while read -r line; do log "  $line"; done
  exit 1
fi

# Métadonnées snapshot
META="$(mktemp)"
trap 'rm -f "$META"' EXIT
cat > "$META" <<EOF
date=$(date -Iseconds)
host=${HOST_TAG}
backup_monorepo_root=${BACKUP_MONOREPO_ROOT}
ansible_root=${ROOT}
user=$(whoami)
exclude_file=${BACKUP_RCLONE_EXCLUDE_FILE}
EOF
rclone copyto "$META" "${REMOTE_DEST}/BACKUP_INFO.txt" --config "$RCLONE_CONFIG"

if [[ -n "${BACKUP_EXTRA_PATHS:-}" ]]; then
  IFS=':' read -ra EXTRA <<< "$BACKUP_EXTRA_PATHS"
  for p in "${EXTRA[@]}"; do
    [[ -z "$p" ]] && continue
    if [[ -e "$p" ]]; then
      log "  + extra hors monorepo: $p"
      rclone copy "$p" "${REMOTE_DEST}/extra/$(basename "$p")" \
        --config "$RCLONE_CONFIG" --log-file "$LOG_FILE" --log-level INFO || \
        log "  WARN: extra $p échoué"
    else
      log "  WARN: chemin extra absent: $p"
    fi
  done
fi

log "OK: copie terminée → $REMOTE_MONOREPO"

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
