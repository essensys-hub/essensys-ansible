#!/usr/bin/env bash
# Vérifie que les fichiers SOPS sont chiffrés et qu'aucun secret clair n'apparaît dans le diff Git.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

FAIL=0

echo "==> Fichiers SOPS attendus"
for f in secrets/cloud/essensys.sops.yaml; do
  if [[ ! -f "$f" ]]; then
    echo "MISSING: $f"
    FAIL=1
    continue
  fi
  if ! grep -q 'sops:' "$f"; then
    echo "NOT ENCRYPTED: $f (metadata sops: absente)"
    FAIL=1
  else
    echo "OK: $f (metadata sops présente)"
  fi
done

echo ""
echo "==> Déchiffrement test (nécessite SOPS_AGE_KEY_FILE)"
if [[ -n "${SOPS_AGE_KEY_FILE:-}" && -f "${SOPS_AGE_KEY_FILE}" ]]; then
  if sops -d secrets/cloud/essensys.sops.yaml >/dev/null 2>&1; then
    echo "OK: decrypt secrets/cloud/essensys.sops.yaml"
  else
    echo "FAIL: impossible de déchiffrer secrets/cloud/essensys.sops.yaml"
    FAIL=1
  fi
else
  echo "SKIP: SOPS_AGE_KEY_FILE non défini"
fi

echo ""
echo "==> Scan anti-secret-clair dans diff Git (staged + unstaged)"
if git diff HEAD 2>/dev/null | grep -iE 'NRAL|NRAK|GOCSPX-' | grep -v '\.sops\.yaml' | grep -v 'ENC\['; then
  echo "FAIL: motif secret clair détecté dans git diff (hors blobs SOPS)"
  FAIL=1
else
  echo "OK: aucun motif secret clair évident dans git diff"
fi

if [[ "$FAIL" -ne 0 ]]; then
  exit 1
fi

echo ""
echo "verify-sops: OK"
