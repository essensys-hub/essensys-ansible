#!/usr/bin/env bash
# Deploy Turnstile registration protection to OVH (cloud-backend + support-site SPA).
# Does not print secret values.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-$ROOT/essensys-ansible/.age/keys.txt}"
OVH_HOST="${OVH_HOST:-ubuntu@mon.essensys.fr}"
OVH_KH="${OVH_KH:-/tmp/essensys_ovh_known_hosts}"
RSYNC_SSH=(ssh -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$OVH_KH")

SOPS_FILE="$ROOT/essensys-ansible/secrets/cloud/essensys.sops.yaml"
TMP_SOPS="$(mktemp)"
chmod 600 "$TMP_SOPS"
trap 'rm -f "$TMP_SOPS" /tmp/essensys-turnstile-env.sh' EXIT

sops -d "$SOPS_FILE" > "$TMP_SOPS"

python3 - "$TMP_SOPS" <<'PY'
import re, shlex, sys
from pathlib import Path
text = Path(sys.argv[1]).read_text()
vals = {}
for line in text.splitlines():
    if line.startswith("sops:"):
        break
    if not line or line[0] in " \t#" or ":" not in line:
        continue
    k, v = line.split(":", 1)
    k = k.strip()
    v = v.strip().strip('"').strip("'")
    if k in ("TURNSTILE_SECRET_KEY", "VITE_TURNSTILE_SITE_KEY", "vault_turnstile_secret_key", "vault_turnstile_site_key"):
        vals[k] = v

secret = vals.get("TURNSTILE_SECRET_KEY") or vals.get("vault_turnstile_secret_key")
site = vals.get("VITE_TURNSTILE_SITE_KEY") or vals.get("vault_turnstile_site_key")
if not secret or not site:
    raise SystemExit("missing Turnstile keys in SOPS")
out = Path("/tmp/essensys-turnstile-env.sh")
out.write_text(
    "export TURNSTILE_SECRET_KEY=" + shlex.quote(secret) + "\n"
    "export VITE_TURNSTILE_SITE_KEY=" + shlex.quote(site) + "\n"
)
out.chmod(0o600)
print(f"loaded secret_len={len(secret)} site_len={len(site)}")
PY

# shellcheck disable=SC1091
source /tmp/essensys-turnstile-env.sh

echo "=== [1/4] Sync cloud-backend source ==="
# Exclude only the root-level local binary named "server" (not cmd/server/).
rsync --delete -az \
  --exclude .git --exclude node_modules --exclude dist --exclude /server \
  --exclude .artifacts --exclude test-results \
  -e "${RSYNC_SSH[*]}" \
  "$ROOT/essensys-user-portal-backend/" \
  "$OVH_HOST:/tmp/cloud-backend-src/"

"${RSYNC_SSH[@]}" "$OVH_HOST" \
  'sudo rsync -a --delete /tmp/cloud-backend-src/ /opt/essensys/cloud-backend-src/ && sudo chown -R essensys:essensys /opt/essensys/cloud-backend-src'

echo "=== [2/4] Patch .env, build backend, restart ==="
B64_SECRET="$(printf '%s' "$TURNSTILE_SECRET_KEY" | base64 | tr -d '\n')"
"${RSYNC_SSH[@]}" "$OVH_HOST" "B64_SECRET='$B64_SECRET' bash -s" <<'REMOTE'
set -euo pipefail
SECRET="$(printf '%s' "$B64_SECRET" | base64 -d)"
ENVF=/opt/essensys/cloud-backend/.env
sudo cp -a "$ENVF" "${ENVF}.bak-turnstile-$(date +%Y%m%d%H%M%S)"
export SECRET ENVF
sudo -E python3 - <<'PY'
import os
from pathlib import Path
p = Path(os.environ["ENVF"])
secret = os.environ["SECRET"]
skip = {
    "ENV",
    "TURNSTILE_SECRET_KEY",
    "TURNSTILE_DISABLED",
    "REGISTER_RATE_LIMIT",
    "REGISTER_RATE_WINDOW_SECONDS",
}
lines = p.read_text().splitlines()
out = [ln for ln in lines if ln.split("=", 1)[0] not in skip]
out += [
    "ENV=production",
    "TURNSTILE_SECRET_KEY=" + secret,
    "TURNSTILE_DISABLED=false",
    "REGISTER_RATE_LIMIT=5",
    "REGISTER_RATE_WINDOW_SECONDS=3600",
]
p.write_text("\n".join(out) + "\n")
PY
sudo chown essensys:essensys "$ENVF"
sudo chmod 600 "$ENVF"
sudo python3 - <<'PY'
from pathlib import Path
d = {}
for ln in Path("/opt/essensys/cloud-backend/.env").read_text().splitlines():
    if "=" in ln and not ln.startswith("#"):
        k, v = ln.split("=", 1)
        d[k] = v
for k in ("ENV", "TURNSTILE_SECRET_KEY", "TURNSTILE_DISABLED"):
    v = d.get(k, "")
    print(f"{k}: present={bool(v)} len={len(v)}")
PY
cd /opt/essensys/cloud-backend-src
sudo -u essensys bash -lc 'export PATH=/usr/local/go/bin:$PATH; go build -buildvcs=false -o /tmp/cloud-server ./cmd/server'
sudo install -o essensys -g essensys -m 0755 /tmp/cloud-server /opt/essensys/cloud-backend/cloud-server
sudo systemctl restart essensys-cloud-backend
sleep 2
systemctl is-active essensys-cloud-backend
curl -sf http://127.0.0.1:8080/api/portal/health
echo
REMOTE

echo "=== [3/4] Build support-site SPA ==="
cd "$ROOT/essensys-support-site/site"
if [[ ! -d node_modules ]]; then
  npm ci
fi
VITE_TURNSTILE_SITE_KEY="$VITE_TURNSTILE_SITE_KEY" npm run build

echo "=== [4/4] Deploy SPA dist ==="
rsync -az --delete -e "${RSYNC_SSH[*]}" \
  "$ROOT/essensys-support-site/site/dist/" \
  "$OVH_HOST:/tmp/frontend-dist/"
"${RSYNC_SSH[@]}" "$OVH_HOST" \
  'sudo rsync -a --delete /tmp/frontend-dist/ /opt/essensys/frontend/dist/ && sudo chown -R essensys:essensys /opt/essensys/frontend/dist && ls /opt/essensys/frontend/dist/assets | tail -5'

echo "=== Smoke ==="
curl -sS -X POST https://www.essensys.fr/api/auth/register \
  -H 'Content-Type: application/json' \
  -d '{"email":"turnstile-smoke-bot@example.com","password":"test-pass-1234"}' \
  -w '\nHTTP:%{http_code}\n' | head -c 500
echo
curl -sS -o /dev/null -w 'www:%{http_code}\n' https://www.essensys.fr/
curl -sS https://mon.essensys.fr/api/portal/health; echo
"${RSYNC_SSH[@]}" "$OVH_HOST" \
  'grep -l challenges.cloudflare.com /opt/essensys/frontend/dist/assets/*.js 2>/dev/null | wc -l'
echo "DONE"
