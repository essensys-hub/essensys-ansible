#!/bin/bash
# Script de diagnostic pour vérifier les endpoints MCP
# Version: 1.0.1

set -e

SCRIPT_VERSION="1.0.1"
SCRIPT_NAME="mcp-diagnose-endpoints.sh"
SCRIPT_REPO="https://raw.githubusercontent.com/essensys-hub/essensys-ansible/V.1.2.2/docs/mcp-diagnose-endpoints.sh"

MCP_TOKEN=$(sudo cat /etc/essensys/mcp.token 2>/dev/null || echo "")
MCP_PORT=${MCP_PORT:-8083}

if [ -z "$MCP_TOKEN" ]; then
    echo "ERREUR: Token MCP non trouvé dans /etc/essensys/mcp.token"
    exit 1
fi

echo "=== Diagnostic des endpoints MCP ==="
echo "Version du script: $SCRIPT_VERSION"
echo "Port: $MCP_PORT"
echo "Token: ${MCP_TOKEN:0:10}..."
echo ""

# Vérifier si une version plus récente est disponible
echo "0. Vérification de la version du script..."
CURRENT_VERSION="$SCRIPT_VERSION"
REMOTE_VERSION=$(curl -s "$SCRIPT_REPO" 2>/dev/null | grep "^SCRIPT_VERSION=" | head -1 | cut -d'"' -f2 || echo "")

if [ -n "$REMOTE_VERSION" ] && [ "$REMOTE_VERSION" != "$CURRENT_VERSION" ]; then
    echo "   ⚠ Version disponible: $REMOTE_VERSION (vous avez: $CURRENT_VERSION)"
    echo "   → Mettez à jour avec: curl -o $SCRIPT_NAME $SCRIPT_REPO && chmod +x $SCRIPT_NAME"
else
    echo "   ✓ Version à jour ($CURRENT_VERSION)"
fi
echo ""

# Vérifier que le service est actif ou que le processus est en cours d'exécution
echo "1. Vérification du service MCP..."
SERVICE_ACTIVE=false
PROCESS_RUNNING=false

# Vérifier le statut systemd
if systemctl is-active --quiet essensys-mcp 2>/dev/null; then
    SERVICE_ACTIVE=true
fi

# Vérifier si le processus est en cours d'exécution
if pgrep -f "essensys-mcp" > /dev/null; then
    PROCESS_RUNNING=true
fi

if [ "$SERVICE_ACTIVE" = true ]; then
    echo "   ✓ Service systemd actif"
elif [ "$PROCESS_RUNNING" = true ]; then
    echo "   ⚠ Service systemd inactif mais processus en cours d'exécution"
    echo "   → Le service a probablement été lancé manuellement"
else
    echo "   ✗ Service inactif et aucun processus trouvé"
    exit 1
fi

# Vérifier que le port est en écoute
echo ""
echo "2. Vérification du port $MCP_PORT..."
if ss -tlnp | grep -q ":$MCP_PORT "; then
    echo "   ✓ Port $MCP_PORT en écoute"
    ss -tlnp | grep ":$MCP_PORT "
else
    echo "   ✗ Port $MCP_PORT non en écoute"
    exit 1
fi

# Test de l'endpoint /sse (GET)
echo ""
echo "3. Test de l'endpoint /sse (GET)..."
# SSE streams stay open, so we use --max-time to avoid hanging
SSE_RESPONSE=$(curl -s -k -w "\n%{http_code}" \
    -H "Authorization: Bearer $MCP_TOKEN" \
    -H "Accept: text/event-stream" \
    -X GET \
    --max-time 2 \
    "http://localhost:$MCP_PORT/sse" 2>&1 | tail -1)

if [ "$SSE_RESPONSE" = "200" ]; then
    echo "   ✓ GET /sse retourne 200 (stream SSE actif)"
elif [ "$SSE_RESPONSE" = "000" ]; then
    # Connection timeout - this is normal for SSE streams
    echo "   ⚠ GET /sse timeout (normal pour un stream SSE qui reste ouvert)"
    echo "   → L'endpoint SSE fonctionne correctement (timeout attendu)"
else
    echo "   ✗ GET /sse retourne $SSE_RESPONSE"
fi

# Test de l'endpoint /messages (POST avec initialize)
echo ""
echo "4. Test de l'endpoint /messages (POST)..."
MESSAGES_RESPONSE=$(curl -s -k -w "\n%{http_code}" \
    -H "Authorization: Bearer $MCP_TOKEN" \
    -H "Content-Type: application/json" \
    -X POST \
    -d '{
      "jsonrpc": "2.0",
      "id": 1,
      "method": "initialize",
      "params": {
        "protocolVersion": "2024-11-05",
        "capabilities": {},
        "clientInfo": {
          "name": "test-client",
          "version": "1.0.0"
        }
      }
    }' \
    "http://localhost:$MCP_PORT/messages" 2>&1)

HTTP_CODE=$(echo "$MESSAGES_RESPONSE" | tail -1)
BODY=$(echo "$MESSAGES_RESPONSE" | head -n -1)

echo "   Code HTTP: $HTTP_CODE"
if [ "$HTTP_CODE" = "200" ]; then
    echo "   ✓ POST /messages retourne 200"
    echo "   Réponse: $BODY" | head -c 200
    echo ""
else
    echo "   ✗ POST /messages retourne $HTTP_CODE"
    echo "   Réponse complète:"
    echo "$BODY"
fi

# Test avec différents chemins
echo ""
echo "5. Test avec différents chemins..."
for path in "/" "/mcp" "/api/mcp"; do
    TEST_RESPONSE=$(curl -s -k -w "\n%{http_code}" \
        -H "Authorization: Bearer $MCP_TOKEN" \
        -X GET \
        "http://localhost:$MCP_PORT$path" 2>&1 | tail -1)
    echo "   GET $path: $TEST_RESPONSE"
done

echo ""
echo "=== Diagnostic terminé ==="
