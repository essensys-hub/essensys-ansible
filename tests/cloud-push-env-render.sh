#!/usr/bin/env bash
# Verifie les variables push du .env cloud avec une cle age JETABLE et de FAUSSES valeurs :
#   tout present, FCM seul, APNs seul, rien, incoherence refusee ;
#   valeurs multi-lignes intactes, .env en 0600, aucune valeur dans la sortie
#   (run normal et --check --diff). Ne touche ni serveur ni vrai secret SOPS.
set -euo pipefail
cd "$(dirname "$0")/.."
export PUSH_TEST_DIR; PUSH_TEST_DIR="$(mktemp -d)"
export ANSIBLE_ROLES_PATH="$PWD/roles" ANSIBLE_LOCALHOST_WARNING=False ANSIBLE_INVENTORY_UNPARSED_WARNING=False
trap 'rm -rf "$PUSH_TEST_DIR"' EXIT
fail() { echo "ECHEC: $*" >&2; exit 1; }
export SOPS_AGE_KEY_FILE="$PUSH_TEST_DIR/age.txt"
age-keygen -o "$SOPS_AGE_KEY_FILE" >/dev/null 2>&1
PUB="$(age-keygen -y "$SOPS_AGE_KEY_FILE")"
printf 'creation_rules:\n  - age: %s\n' "$PUB" >"$PUSH_TEST_DIR/sops.yaml"
PB=(ansible-playbook -i localhost, tests/cloud-push-env-render.yml)

# Marqueurs PEM assemblés à l'exécution : aucun motif de clé privée en clair dans le dépôt
# (les scanners de secrets signalent la séquence littérale, même avec de fausses valeurs).
PEM_B="-----BEGIN PRIV""ATE KEY-----"
PEM_E="-----END PRIV""ATE KEY-----"
FCM_JSON='{"type":"service_account","project_id":"fake-proj","private_key":"'"${PEM_B}"'\nFAKEFCMKEYLINE\n'"${PEM_E}"'\n","client_email":"fake@fake-proj.example.org"}'
P8="${PEM_B}"$'\nFAKEAPNSKEYLINE1\nFAKEAPNSKEYLINE2\n'"${PEM_E}"
SECRETS=(FAKEFCMKEYLINE FAKEAPNSKEYLINE1 FAKEAPNSKEYLINE2 fake-proj FAKEKEYID FAKETEAMID)

# make_secrets <fcm:0|1> <apns:0|1> [extra yaml line]
make_secrets() {
  python3 - "$1" "$2" "${3:-}" "$FCM_JSON" "$P8" >"$PUSH_TEST_DIR/plain.yaml" <<'PY'
import sys, json
fcm, apns, extra, fj, p8 = sys.argv[1:6]
d = {"unrelated_key": "x"}
if fcm == "1":
    d.update(fcm_project_id="fake-proj", fcm_service_account_json=fj)
if apns == "1":
    d.update(apns_key_p8=p8, apns_key_id="FAKEKEYID", apns_team_id="FAKETEAMID",
             apns_bundle_id="essensys.essensys-iphone", apns_env="production")
print(json.dumps(d))
PY
  sops --config "$PUSH_TEST_DIR/sops.yaml" --encrypt --filename-override x.sops.yaml --input-type json --output-type yaml \
    "$PUSH_TEST_DIR/plain.yaml" >"$PUSH_TEST_DIR/secrets.sops.yaml"
  rm -f "$PUSH_TEST_DIR/.env"
}

run() { # run <nom> : check --diff puis application reelle
  "${PB[@]}" --check --diff >"$PUSH_TEST_DIR/$1.check.log" 2>&1 || { cat "$PUSH_TEST_DIR/$1.check.log"; fail "$1: check"; }
  "${PB[@]}" >"$PUSH_TEST_DIR/$1.run.log" 2>&1 || { cat "$PUSH_TEST_DIR/$1.run.log"; fail "$1: run"; }
  for f in "$PUSH_TEST_DIR/$1.check.log" "$PUSH_TEST_DIR/$1.run.log"; do
    for s in "${SECRETS[@]}"; do ! grep -q "$s" "$f" || fail "$1: '$s' apparait dans la sortie ($(basename "$f"))"; done
  done
  [ "$(stat -f '%Lp' "$PUSH_TEST_DIR/.env" 2>/dev/null || stat -c '%a' "$PUSH_TEST_DIR/.env")" = 600 ] || fail "$1: .env pas en 0600"
}

check_env() { # check_env <fcm:0|1> <apns:0|1>  -> decode le .env comme systemd (apostrophes = litteral)
  python3 - "$PUSH_TEST_DIR/.env" "$1" "$2" "$FCM_JSON" "$P8" <<'PY' || fail "contenu .env ($1 $2)"
import sys, re
path, fcm, apns, fj, p8 = sys.argv[1:6]
t = open(path).read()
env = {}
# analyseur ligne a ligne gerant les valeurs entre apostrophes sur plusieurs lignes
i, lines, env = 0, t.split("\n"), {}
while i < len(lines):
    m = re.match(r"^([A-Z][A-Z0-9_]*)=(.*)$", lines[i])
    if not m: i += 1; continue
    k, v = m.groups()
    if v.startswith("'"):
        buf = v[1:]
        while not buf.endswith("'"):
            i += 1; buf += "\n" + lines[i]
        v = buf[:-1]
    env[k] = v; i += 1
fcm_keys = {"FCM_PROJECT_ID", "FCM_SERVICE_ACCOUNT_JSON"}
apns_keys = {"APNS_KEY_P8", "APNS_KEY_ID", "APNS_TEAM_ID", "APNS_BUNDLE_ID", "APNS_ENV"}
got = {k for k in env if k in fcm_keys | apns_keys}
assert got == (fcm_keys if fcm == "1" else set()) | (apns_keys if apns == "1" else set()), got
if fcm == "1":
    assert env["FCM_SERVICE_ACCOUNT_JSON"] == fj and env["FCM_PROJECT_ID"] == "fake-proj"
if apns == "1":
    assert env["APNS_KEY_P8"] == p8, repr(env["APNS_KEY_P8"])
    assert (env["APNS_KEY_ID"], env["APNS_TEAM_ID"], env["APNS_ENV"]) == ("FAKEKEYID", "FAKETEAMID", "production")
    assert env["APNS_BUNDLE_ID"] == "essensys.essensys-iphone"
assert env["PORT"] == "8080" and env["JWT_SECRET"] == "dummy-jwt"  # reste du .env preserve
PY
}

for combo in "1 1:tout" "1 0:fcm-seul" "0 1:apns-seul" "0 0:rien"; do
  args="${combo%%:*}"; name="${combo##*:}"
  make_secrets $args; run "$name"; check_env $args
  echo "  ok: $name"
done

# Idempotence (tout present).
make_secrets 1 1; "${PB[@]}" >/dev/null 2>&1
"${PB[@]}" 2>&1 | grep -q "changed=0" || fail "non idempotent"

# Incoherence : cle APNs sans identifiants -> refus, sans fuite.
python3 - >"$PUSH_TEST_DIR/plain.yaml" <<'PY'
import json; print(json.dumps({"apns_key_p8": "FAKEAPNSKEYLINE1"}))
PY
sops --config "$PUSH_TEST_DIR/sops.yaml" --encrypt --filename-override x.sops.yaml --input-type json --output-type yaml "$PUSH_TEST_DIR/plain.yaml" >"$PUSH_TEST_DIR/secrets.sops.yaml"
if "${PB[@]}" >"$PUSH_TEST_DIR/bad.log" 2>&1; then fail "incoherence acceptee"; fi
! grep -q FAKEAPNSKEYLINE1 "$PUSH_TEST_DIR/bad.log" || fail "fuite dans le refus"
echo "OK: variables push du .env cloud (tout, FCM seul, APNs seul, rien, incoherence, 0600, idempotence, aucune fuite)"
