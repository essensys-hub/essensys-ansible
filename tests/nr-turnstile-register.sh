#!/usr/bin/env bash
# NR-essensys-ansible-22 (#22) : l'inscription publique exige Turnstile.
#   1. le build du site reçoit VITE_TURNSTILE_SITE_KEY depuis vault_turnstile_site_key ;
#   2. le build échoue si la clé est absente (assert) ;
#   3. le .env du backend reçoit TURNSTILE_SECRET_KEY et TURNSTILE_DISABLED=false, sans log.
set -euo pipefail
cd "$(dirname "$0")/.."
fail() { echo "ECHEC NR-essensys-ansible-22: $*" >&2; exit 1; }
FE=roles/frontend/tasks/main.yml BE=roles/backend/tasks/main.yml
python3 - "$FE" "$BE" <<'PY' || exit 1
import sys, yaml
fe = yaml.safe_load(open(sys.argv[1])); be = yaml.safe_load(open(sys.argv[2]))
def err(m): print("ECHEC NR-essensys-ansible-22:", m, file=sys.stderr); sys.exit(1)
build = next((t for t in fe if t.get("command") == "npm run build"), None) or err("tâche npm run build absente")
if "vault_turnstile_site_key" not in str(build.get("environment", {}).get("VITE_TURNSTILE_SITE_KEY", "")):
    err("VITE_TURNSTILE_SITE_KEY non passé au build")
names = [t.get("name", "") for t in fe]
ia = next((i for i, t in enumerate(fe) if "assert" in t and "vault_turnstile_site_key" in str(t["assert"])), None)
if ia is None or ia > fe.index(build): err("assert sur vault_turnstile_site_key manquant avant le build")
ts = next((t for t in be if "TURNSTILE_SECRET_KEY" in str(t.get("loop", ""))), None) or err("TURNSTILE_SECRET_KEY absent du .env backend")
if not ts.get("no_log"): err("la tâche secrète doit être no_log")
if "TURNSTILE_DISABLED" not in str(ts["loop"]) or "'false'" not in str(ts["loop"]).replace('"', "'"): err("TURNSTILE_DISABLED=false absent")
tpl = open("roles/cloud_backend/templates/cloud-backend.env.j2").read()
if "TURNSTILE_SECRET_KEY={{ vault_turnstile_secret_key" not in tpl or "TURNSTILE_DISABLED=false" not in tpl:
    err("le .env du backend de prod (cloud_backend) n'a pas TURNSTILE_SECRET_KEY / TURNSTILE_DISABLED=false")
print("OK NR-essensys-ansible-22")
PY
