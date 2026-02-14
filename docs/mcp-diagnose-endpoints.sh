#!/bin/bash
# Script de diagnostic pour vérifier les endpoints MCP

set -e

MCP_TOKEN=$(sudo cat /etc/essensys/mcp.token 2>/dev/null || echo "")
MCP_PORT=${MCP_PORT:-8083}

if [ -z "$MCP_TOKEN" ]; then
    echo "ERREUR: Token MCP non trouvé dans /etc/essensys/mcp.token"
    exit 1
fi

echo "=== Diagnostic des endpoints MCP ==="
echo "Port: $MCP_PORT"
echo "Token: ${MCP_TOKEN:0:10}..."
echo ""

# Vérifier que le service est actif
echo "1. Vérification du service MCP..."
if systemctl is-active --quiet essensys-mcp; then
    echo "   ✓ Service actif"
else
    echo "   ✗ Service inactif"
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
SSE_RESPONSE=$(curl -s -k -w "\n%{http_code}" \
    -H "Authorization: Bearer $MCP_TOKEN" \
    -H "Accept: text/event-stream" \
    -X GET \
    "http://localhost:$MCP_PORT/sse" 2>&1 | tail -1)

if [ "$SSE_RESPONSE" = "200" ] || [ "$SSE_RESPONSE" = "200" ]; then
    echo "   ✓ GET /sse retourne $SSE_RESPONSE"
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
