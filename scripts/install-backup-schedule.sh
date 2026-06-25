#!/usr/bin/env bash
# Installe launchd macOS : backup Synology tous les jours à 02:00.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLIST_SRC="$ROOT/launchd/com.essensys.syno-backup.plist"
PLIST_DST="$HOME/Library/LaunchAgents/com.essensys.syno-backup.plist"
BACKUP_SCRIPT="$ROOT/scripts/backup-to-syno.sh"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Ce script installe launchd (macOS). Sur Linux, utilisez cron:"
  echo "  0 2 * * * $BACKUP_SCRIPT >> \$HOME/essensys-backup.log 2>&1"
  exit 1
fi

if [[ ! -x "$BACKUP_SCRIPT" ]]; then
  chmod +x "$BACKUP_SCRIPT" "$ROOT/scripts/backup-syno-init.sh"
fi

mkdir -p "$HOME/Library/LaunchAgents"
mkdir -p "$HOME/Library/Logs/essensys-backup"

# Génère plist avec chemins absolus
sed \
  -e "s|@ESSENSYS_ANSIBLE_ROOT@|$ROOT|g" \
  -e "s|@HOME@|$HOME|g" \
  "$PLIST_SRC" > "$PLIST_DST"

launchctl bootout "gui/$(id -u)" "$PLIST_DST" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST_DST"
launchctl enable "gui/$(id -u)/com.essensys.syno-backup" 2>/dev/null || true

echo "Installé: $PLIST_DST"
echo "Prochain run: tous les jours à 02:00 (heure locale)"
echo ""
echo "Test immédiat:"
echo "  launchctl kickstart -k gui/$(id -u)/com.essensys.syno-backup"
echo ""
echo "Logs: $HOME/Library/Logs/essensys-backup/"
