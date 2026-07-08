#!/usr/bin/env bash
# Déploiement local scénarios → OVH puis CM5 (sans push GitHub)
set -euo pipefail

ROOT="${ESSENSYS_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
CM5_HOST="${CM5_HOST:-essensys@192.168.0.14}"
CM5_KEY="${CM5_KEY:-$HOME/.ssh/id_ed25519}"
OVH_HOST="${OVH_HOST:-ubuntu@test.essensys.fr}"
SSH_CM5=(ssh -i "$CM5_KEY" -o StrictHostKeyChecking=accept-new "$CM5_HOST")
RSYNC_SSH="ssh -i $CM5_KEY -o StrictHostKeyChecking=accept-new"

RSYNC_EX=(--delete -az --exclude .git --exclude node_modules --exclude dist)

echo "=== [1/6] OVH — sync cloud-backend ==="
rsync "${RSYNC_EX[@]}" \
  "$ROOT/essensys-user-portal-backend/" \
  "$OVH_HOST:/tmp/cloud-backend-src/"
ssh "$OVH_HOST" bash -s <<'REMOTE'
set -euo pipefail
sudo rsync -a --delete /tmp/cloud-backend-src/ /opt/essensys/cloud-backend-src/
sudo chown -R essensys:essensys /opt/essensys/cloud-backend-src
REMOTE

echo "=== [2/6] OVH — build + restart cloud-backend (migration 009) ==="
ssh "$OVH_HOST" bash -s <<'REMOTE'
set -euo pipefail
cd /opt/essensys/cloud-backend-src
sudo -u essensys /usr/local/go/bin/go build -buildvcs=false -o /tmp/cloud-server ./cmd/server
sudo install -o essensys -g essensys -m 755 /tmp/cloud-server /opt/essensys/cloud-backend/cloud-server
sudo systemctl restart essensys-cloud-backend
sleep 3
systemctl is-active essensys-cloud-backend
test -f migrations/009_scenarios_sync_profile.sql && echo migration 009 present
REMOTE

echo "=== [3/6] OVH — sync + build portal-frontend ==="
rsync "${RSYNC_EX[@]}" \
  "$ROOT/essensys-user-portal-frontend/" \
  "$OVH_HOST:/tmp/portal-frontend-src/"
ssh "$OVH_HOST" bash -s <<'REMOTE'
set -euo pipefail
sudo rsync -a --delete /tmp/portal-frontend-src/ /opt/essensys/portal-frontend-src/
sudo chown -R essensys:essensys /opt/essensys/portal-frontend-src
sudo -u essensys bash -c 'cd /opt/essensys/portal-frontend-src && npm install --silent && VITE_PORTAL_ROOT=true npm run build'
sudo rsync -a --delete /opt/essensys/portal-frontend-src/dist/ /opt/essensys/portal-frontend/dist/
sudo chown -R essensys:essensys /opt/essensys/portal-frontend/dist
REMOTE

echo "=== [4/6] CM5 — sync + build server-backend ==="
rsync "${RSYNC_EX[@]}" -e "$RSYNC_SSH" \
  "$ROOT/essensys-server-backend/" \
  "$CM5_HOST:/home/essensys/essensys-server-backend/"
"${SSH_CM5[@]}" bash -s <<'REMOTE'
set -euo pipefail
cd /home/essensys/essensys-server-backend
export PATH="/usr/local/go/bin:$PATH"
export CGO_ENABLED=0
go mod tidy
go build -o /opt/essensys/backend/server ./cmd/server
docker restart essensys-backend
sleep 2
docker ps --filter name=essensys-backend --format '{{.Status}}'
test -f internal/scenario/launch.go && echo scenario package OK
REMOTE

echo "=== [5/6] Build LAN frontend (local) → CM5 ==="
cd "$ROOT/essensys-server-frontend"
npm install --silent
npm run build
rsync -az --delete -e "$RSYNC_SSH" dist/ "$CM5_HOST:/opt/data/frontend/"

echo "=== [6/6] Smoke checks ==="
"${SSH_CM5[@]}" 'curl -sf http://127.0.0.1:7070/api/scenarios | head -c 200; echo'
ssh "$OVH_HOST" 'curl -sf http://127.0.0.1:8080/api/portal/health 2>/dev/null || curl -sf http://127.0.0.1:8080/health; echo'
ssh "$OVH_HOST" "psql -U essensys -d essensys_db -tAc \"SELECT name, enabled FROM sync_profiles WHERE name='Scénarios'\" 2>/dev/null" || \
  ssh "$OVH_HOST" "sudo -u postgres psql essensys_db -tAc \"SELECT name, enabled FROM sync_profiles WHERE name='Scénarios'\" 2>/dev/null" || \
  echo 'verify migration 009 manually (psql)'

echo "=== Déploiement terminé ==="
