#!/usr/bin/env bash
# Configure rclone → Synology SMB (config Synology via SOPS).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RCLONE_CONFIG="$ROOT/config/rclone.conf"

# shellcheck source=/dev/null
source "$ROOT/scripts/load-backup-syno-config.sh"

mkdir -p "$(dirname "$RCLONE_CONFIG")"

if rclone listremotes --config "$RCLONE_CONFIG" 2>/dev/null | grep -q "^${RCLONE_REMOTE}:$"; then
  echo "Remote rclone '${RCLONE_REMOTE}' déjà présent dans $RCLONE_CONFIG"
  echo "Mise à jour mot de passe si syno_pass a changé dans SOPS..."
  rclone config password "$RCLONE_REMOTE" pass "$SYNO_PASS" --config "$RCLONE_CONFIG"
else
  echo "Création remote rclone '${RCLONE_REMOTE}' → //$SYNO_HOST/$SYNO_SHARE"
  rclone config create "$RCLONE_REMOTE" smb \
    host="$SYNO_HOST" \
    user="$SYNO_USER" \
    pass="$SYNO_PASS" \
    share="$SYNO_SHARE" \
    --config "$RCLONE_CONFIG"
fi

echo ""
echo "Test connexion:"
rclone lsd "${RCLONE_REMOTE}:" --config "$RCLONE_CONFIG" || {
  echo "Échec — vérifiez syno_* dans secrets/operator/backup.syno.sops.yaml"
  exit 1
}

echo ""
echo "OK. Lancer: $ROOT/scripts/backup-to-syno.sh"
echo "Planifier: $ROOT/scripts/install-backup-schedule.sh"
