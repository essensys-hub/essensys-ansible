#!/bin/bash
# Script pour tester la connexion au serveur MCP depuis une workstation distante
# Utile pour vérifier la configuration OpenClaw

set -e

# Configuration
ESSENSYS_SERVER_IP="${ESSENSYS_SERVER_IP:-essensys-server}"
MCP_PORT="${MCP_PORT:-8083}"
MCP_URL="http://${ESSENSYS_SERVER_IP}:${MCP_PORT}"

# Couleurs
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
}

# Demander le token si non fourni
if [ -z "$MCP_TOKEN" ]; then
    log_info "Token MCP non fourni via variable d'environnement"
    log_info "Vous pouvez le récupérer sur le Raspberry Pi avec:"
    log_info "  ssh essensys@${ESSENSYS_SERVER_IP} 'sudo cat /etc/essensys/mcp.token'"
    echo ""
    read -p "Entrez le token MCP: " MCP_TOKEN
    echo ""
fi

if [ -z "$MCP_TOKEN" ]; then
    log_error "Token MCP requis"
    exit 1
fi

log_info "Configuration:"
log_info "  Serveur: $ESSENSYS_SERVER_IP"
log_info "  Port: $MCP_PORT"
log_info "  URL: $MCP_URL"
log_info "  Token: ${MCP_TOKEN:0:10}..."
echo ""

# Test 1: Vérifier que le serveur est accessible
log_info "Test 1: Vérification de l'accessibilité du serveur..."
if curl -k -s --max-time 5 "$MCP_URL/sse" > /dev/null 2>&1; then
    log_info "✓ Serveur accessible"
else
    log_error "✗ Serveur non accessible"
    log_info "Vérifiez:"
    log_info "  - Que le serveur MCP est démarré sur le Raspberry Pi"
    log_info "  - Que le port $MCP_PORT est ouvert"
    log_info "  - Que vous êtes sur le même réseau ou VPN"
    exit 1
fi

# Test 2: Vérifier l'authentification
log_info ""
log_info "Test 2: Vérification de l'authentification..."
AUTH_TEST=$(curl -k -s -w "\n%{http_code}" \
  -H "Authorization: Bearer $MCP_TOKEN" \
  -H "Accept: text/event-stream" \
  --max-time 3 \
  "$MCP_URL/sse" 2>&1 | tail -1)

if [ "$AUTH_TEST" = "200" ] || [ "$AUTH_TEST" = "000" ]; then
    log_info "✓ Authentification réussie"
elif [ "$AUTH_TEST" = "401" ]; then
    log_error "✗ Authentification échouée (401 Unauthorized)"
    log_info "Vérifiez que le token est correct"
    exit 1
elif [ "$AUTH_TEST" = "403" ]; then
    log_error "✗ Accès refusé (403 Forbidden)"
    log_info "Le serveur vérifie que vous êtes sur une IP privée"
    log_info "Assurez-vous d'être sur le même réseau local que le Raspberry Pi"
    exit 1
else
    log_warn "⚠ Code HTTP inattendu: $AUTH_TEST"
fi

# Test 3: Tester l'endpoint SSE
log_info ""
log_info "Test 3: Test de l'endpoint SSE..."
SSE_RESPONSE=$(curl -k -s -w "\n%{http_code}" \
  -H "Authorization: Bearer $MCP_TOKEN" \
  -H "Accept: text/event-stream" \
  --max-time 2 \
  "$MCP_URL/sse" 2>&1 | tail -1)

if [ "$SSE_RESPONSE" = "200" ] || [ "$SSE_RESPONSE" = "000" ]; then
    log_info "✓ Endpoint SSE fonctionne"
else
    log_error "✗ Endpoint SSE ne fonctionne pas (code: $SSE_RESPONSE)"
fi

# Afficher les informations de configuration pour OpenClaw
log_info ""
log_info "=========================================="
log_info "Configuration OpenClaw :"
log_info "=========================================="
log_info ""
log_info "Type de transport: SSE (Server-Sent Events)"
log_info "URL de base: $MCP_URL"
log_info "Endpoint SSE: /sse"
log_info "Endpoint Messages: /messages"
log_info "Authentification: Bearer Token"
log_info "Token: $MCP_TOKEN"
log_info ""
log_info "Dans OpenClaw, configurez :"
log_info "  - URL: $MCP_URL"
log_info "  - Transport: SSE"
log_info "  - Headers: Authorization: Bearer $MCP_TOKEN"
log_info ""
log_info "Ou utilisez cette URL complète pour le test :"
log_info "  $MCP_URL/sse"
log_info ""
