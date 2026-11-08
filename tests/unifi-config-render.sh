#!/usr/bin/env bash
# Verifie le bloc `unifi:` de config.yaml avec des valeurs factices :
#   1. structure rendue (enabled, base_url, api_key ; username/password absents) ;
#   2. sections voisines preservees ;
#   3. idempotence ;
#   4. `--check --diff` n'affiche JAMAIS la cle d'API.
set -euo pipefail
cd "$(dirname "$0")/.."
export UNIFI_TEST_DIR; UNIFI_TEST_DIR="$(mktemp -d)"
export ANSIBLE_ROLES_PATH="$PWD/roles" ANSIBLE_LOCALHOST_WARNING=False ANSIBLE_INVENTORY_UNPARSED_WARNING=False
trap 'rm -rf "$UNIFI_TEST_DIR"' EXIT
KEY="FAKE-KEY-0123456789-NOT-A-SECRET"
PB=(ansible-playbook -i localhost, tests/unifi-config-render.yml)
fail() { echo "ECHEC: $*" >&2; exit 1; }

# 4. --check --diff sur un fichier existant sans bloc : la cle ne doit pas fuiter.
"${PB[@]}" --check --diff >"$UNIFI_TEST_DIR/check.log" 2>&1 || { cat "$UNIFI_TEST_DIR/check.log"; fail "check"; }
! grep -q "$KEY" "$UNIFI_TEST_DIR/check.log" || fail "la cle d'API apparait dans --check --diff"
grep -q "ANSIBLE MANAGED BLOCK UNIFI" "$UNIFI_TEST_DIR/check.log" || true

# 1-2. Application reelle (dans le repertoire temporaire).
"${PB[@]}" >"$UNIFI_TEST_DIR/run1.log" 2>&1 || { cat "$UNIFI_TEST_DIR/run1.log"; fail "run"; }
! grep -q "$KEY" "$UNIFI_TEST_DIR/run1.log" || fail "la cle d'API apparait dans la sortie"
CFG="$UNIFI_TEST_DIR/config.yaml"
python3 - "$CFG" "$KEY" <<'PY' || fail "structure"
import sys, re
t = open(sys.argv[1]).read()
try:
    import yaml
    d = yaml.safe_load(t)
    u = d["unifi"]
    assert u == {"enabled": True, "base_url": "https://console.example.org", "api_key": sys.argv[2]}, u
    assert d["server"]["port"] == 7070 and d["light_names"]["path"].endswith("light-names.json")
except ImportError:
    assert "unifi:\n  enabled: true\n  base_url: \"https://console.example.org\"" in t
    assert "username" not in t and "password" not in t
    assert "light_names:" in t and "server:" in t
PY

# 3. Idempotence.
"${PB[@]}" 2>&1 | grep -q "changed=0" || fail "non idempotent"
echo "OK: bloc unifi (structure, sections voisines, idempotence, pas de cle dans --diff)"
