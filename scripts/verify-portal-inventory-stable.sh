#!/usr/bin/env bash
# Wrapper: snapshot portal machine inventory on OVH before/after deploy.
#
#   ./scripts/verify-portal-inventory-stable.sh snapshot before --ip 82.67.136.197
#   ansible-playbook … deploy-portal-stack.yml
#   ./scripts/verify-portal-inventory-stable.sh snapshot after --ip 82.67.136.197
#   ./scripts/verify-portal-inventory-stable.sh verify before after
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BACKEND_SCRIPT="${ESSENSYS_ROOT:-$(cd "$ROOT/.." && pwd)}/essensys-user-portal-backend/scripts/verify-inventory-stable.sh"
STATE_DIR="${VERIFY_INVENTORY_STATE_DIR:-/tmp/essensys-inventory-verify}"
SSH_HOST="${VERIFY_INVENTORY_SSH:-ubuntu@test.essensys.fr}"

mkdir -p "$STATE_DIR"

usage() {
  echo "Usage: $0 snapshot <label> [--ip IP] [--id N] [--email EMAIL]"
  echo "       $0 verify <before-label> <after-label>"
  echo "       $0 restart-check [--ip IP] [--email EMAIL]  # snapshot, restart backend, verify"
  exit "${1:-0}"
}

extra_args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ip|--id|--email)
      extra_args+=("$1" "$2")
      shift 2
      ;;
    -h|--help) usage 0 ;;
    *) break ;;
  esac
done

CMD="${1:-}"
LABEL="${2:-}"

[[ -x "$BACKEND_SCRIPT" ]] || { echo "Missing: $BACKEND_SCRIPT" >&2; exit 1; }

run_backend() {
  VERIFY_INVENTORY_SSH="$SSH_HOST" "$BACKEND_SCRIPT" "$@" "${extra_args[@]}"
}

case "$CMD" in
  snapshot)
    [[ -n "$LABEL" ]] || usage 1
    OUT="$STATE_DIR/${LABEL}.txt"
    run_backend snapshot -o "$OUT"
  ;;
  verify)
    BEFORE="${STATE_DIR}/${LABEL}.txt"
    AFTER="${STATE_DIR}/${3:-}.txt"
    [[ -f "$BEFORE" && -f "$AFTER" ]] || {
      echo "Snapshots not found. Expected:" >&2
      echo "  $BEFORE" >&2
      echo "  $AFTER" >&2
      exit 1
    }
    run_backend verify "$BEFORE" "$AFTER"
  ;;
  restart-check)
    TAG="restart-$(date +%Y%m%d-%H%M%S)"
    BEFORE="$STATE_DIR/${TAG}-before.txt"
    AFTER="$STATE_DIR/${TAG}-after.txt"
    run_backend snapshot -o "$BEFORE"
    echo "Restarting essensys-cloud-backend on OVH…"
    PYTHONNOUSERSITE=1 ansible -i "$ROOT/inventory" essensys \
      -m systemd -a 'name=essensys-cloud-backend state=restarted' -o
    sleep 5
    run_backend snapshot -o "$AFTER"
    run_backend verify "$BEFORE" "$AFTER"
  ;;
  *)
    usage 1
    ;;
esac
