#!/usr/bin/env bash
# Publie mon.essensys.local (mDNS) et met a jour les rewrites AdGuard LAN
# lorsque l'IP DHCP de eth0 change.
set -euo pipefail

IFACE="${ESSENSYS_LAN_IFACE:-eth0}"
FQDN="${ESSENSYS_LAN_FQDN:-mon.essensys.local}"
AG_PORT="${ESSENSYS_ADGUARD_PORT:-3000}"
REWRITE_DOMAINS=(mon.essensys.local mon.essensys.fr)
POLL_SECONDS="${ESSENSYS_LAN_DNS_POLL_SECONDS:-15}"

AVahi_PID=""

cleanup() {
  if [[ -n "${AVahi_PID}" ]] && kill -0 "${AVahi_PID}" 2>/dev/null; then
    kill "${AVahi_PID}" 2>/dev/null || true
    wait "${AVahi_PID}" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

get_ip() {
  ip -4 -o addr show dev "${IFACE}" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -1
}

publish_avahi() {
  local ip="$1"
  if [[ -n "${AVahi_PID}" ]] && kill -0 "${AVahi_PID}" 2>/dev/null; then
    kill "${AVahi_PID}" 2>/dev/null || true
    wait "${AVahi_PID}" 2>/dev/null || true
  fi
  avahi-publish -a -R "${FQDN}" "${ip}" &
  AVahi_PID=$!
}

upsert_adguard_rewrite() {
  local domain="$1"
  local ip="$2"
  local api="$3"
  local list old_answer

  list="$(curl -sf "${api}/rewrite/list" 2>/dev/null || true)"
  [[ -n "${list}" ]] || list='[]'

  old_answer="$(printf '%s' "${list}" | python3 - "${domain}" <<'PY'
import json, sys
domain = sys.argv[1]
raw = sys.stdin.read().strip()
if not raw:
    sys.exit(0)
try:
    data = json.loads(raw)
except json.JSONDecodeError:
    sys.exit(0)
for item in data:
    if item.get("domain") == domain:
        print(item.get("answer", ""))
        break
PY
)"

  if [[ -z "${old_answer}" ]]; then
    curl -sf -X POST "${api}/rewrite/add" \
      -H 'Content-Type: application/json' \
      -d "{\"domain\":\"${domain}\",\"answer\":\"${ip}\",\"enabled\":true}" >/dev/null
    return
  fi

  if [[ "${old_answer}" == "${ip}" ]]; then
    return
  fi

  curl -sf -X PUT "${api}/rewrite/update" \
    -H 'Content-Type: application/json' \
    -d "{\"target\":{\"domain\":\"${domain}\",\"answer\":\"${old_answer}\"},\"update\":{\"domain\":\"${domain}\",\"answer\":\"${ip}\",\"enabled\":true}}" >/dev/null
}

update_adguard_rewrites() {
  local ip="$1"
  local api="http://${ip}:${AG_PORT}/control"
  for domain in "${REWRITE_DOMAINS[@]}"; do
    upsert_adguard_rewrite "${domain}" "${ip}" "${api}" || true
  done
}

LAST_IP=""
while true; do
  ip="$(get_ip)"
  while [[ -z "${ip}" ]]; do
    sleep 3
    ip="$(get_ip)"
  done

  if [[ "${ip}" != "${LAST_IP}" ]]; then
    publish_avahi "${ip}"
    update_adguard_rewrites "${ip}"
    logger -t essensys-lan-dns "eth0=${ip} → mDNS ${FQDN} + AdGuard rewrites"
    LAST_IP="${ip}"
  elif [[ -n "${AVahi_PID}" ]] && ! kill -0 "${AVahi_PID}" 2>/dev/null; then
    publish_avahi "${ip}"
  fi

  sleep "${POLL_SECONDS}"
done
