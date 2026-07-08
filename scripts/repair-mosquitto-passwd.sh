#!/usr/bin/env bash
# Regenerate /opt/data/config/mosquitto/passwd when corrupted or out of sync.
# Run on the CM5 (gateway) as a user with sudo.
#
# Usage:
#   ./repair-mosquitto-passwd.sh                    # password from mqtt_debug_config.json
#   ./repair-mosquitto-passwd.sh 'your-mqtt-password'
set -euo pipefail

CONFIG_DIR="${CONFIG_DIR:-/opt/data/config/mosquitto}"
MOSQUITTO_IMAGE="${MOSQUITTO_IMAGE:-essensyshub/essensys-mosquitto:V.1.3.0}"
CONTAINER="${MOSQUITTO_CONTAINER:-essensys-mosquitto}"
MQTT_USER="${MQTT_USER:-essensys}"
MQTT_DEBUG_CONFIG="${MQTT_DEBUG_CONFIG:-/opt/data/mqtt_debug_config.json}"

if [[ "${1:-}" != "" ]]; then
  MQTT_PASS="$1"
elif [[ -f "$MQTT_DEBUG_CONFIG" ]]; then
  MQTT_PASS="$(python3 -c "import json; print(json.load(open('$MQTT_DEBUG_CONFIG'))['password'])")"
else
  echo "Usage: $0 [password]  (or set mqtt_debug_config.json)" >&2
  exit 1
fi

echo "=== Stop $CONTAINER ==="
sudo docker stop "$CONTAINER" 2>/dev/null || true

echo "=== Regenerate $CONFIG_DIR/passwd (user=$MQTT_USER) ==="
sudo rm -f "$CONFIG_DIR/passwd"
sudo docker run --rm \
  -v "$CONFIG_DIR:/mosquitto/config" \
  -e "MQTT_USER=$MQTT_USER" \
  -e "MQTT_PASS=$MQTT_PASS" \
  "$MOSQUITTO_IMAGE" \
  sh -c 'mosquitto_passwd -c -b /mosquitto/config/passwd "$MQTT_USER" "$MQTT_PASS"'
sudo chmod 644 "$CONFIG_DIR/passwd"

if [[ -f "$MQTT_DEBUG_CONFIG" ]]; then
  echo "=== Sync $MQTT_DEBUG_CONFIG ==="
  MQTT_USER="$MQTT_USER" MQTT_PASS="$MQTT_PASS" MQTT_DEBUG_CONFIG="$MQTT_DEBUG_CONFIG" python3 <<'PY'
import json, os
path = os.environ["MQTT_DEBUG_CONFIG"]
with open(path) as f:
    c = json.load(f)
c["username"] = os.environ["MQTT_USER"]
c["password"] = os.environ["MQTT_PASS"]
with open("/tmp/mqtt_debug_config.json", "w") as f:
    json.dump(c, f, indent=2)
    f.write("\n")
PY
  sudo mv /tmp/mqtt_debug_config.json "$MQTT_DEBUG_CONFIG"
  sudo chown essensys:essensys "$MQTT_DEBUG_CONFIG" 2>/dev/null || true
  sudo chmod 600 "$MQTT_DEBUG_CONFIG"
fi

echo "=== Start $CONTAINER ==="
sudo docker start "$CONTAINER"
sleep 3

if ! sudo docker ps --filter "name=$CONTAINER" --format '{{.Status}}' | grep -qi up; then
  echo "ERROR: $CONTAINER not running — check: sudo tail -20 /opt/data/mosquitto/log/mosquitto.log" >&2
  exit 1
fi

echo "=== Test publish (localhost) ==="
if docker run --rm --network host \
  -e "MQTT_USER=$MQTT_USER" -e "MQTT_PASS=$MQTT_PASS" \
  eclipse-mosquitto:2 \
  sh -c 'mosquitto_pub -h 127.0.0.1 -p 1883 -u "$MQTT_USER" -P "$MQTT_PASS" -t essensys/test/auth -m ok'; then
  echo "OK — MQTT auth works on the CM5."
else
  echo "FAIL — see mosquitto.log" >&2
  sudo tail -10 /opt/data/mosquitto/log/mosquitto.log
  exit 1
fi
