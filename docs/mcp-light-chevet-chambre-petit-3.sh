#!/bin/bash
# Script complet pour allumer la lumière "chevet chambre petit 3"
# Utilise le protocole MCP SSE pour envoyer la commande

set -e

# Configuration
MCP_PORT="${MCP_PORT:-8083}"
MCP_URL="http://localhost:${MCP_PORT}/messages"
SSE_URL="http://localhost:${MCP_PORT}/sse"
TOKEN_FILE="/etc/essensys/mcp.token"

# Couleurs pour l'affichage
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

# Vérifier que le token existe
if [ ! -f "$TOKEN_FILE" ]; then
    log_error "Token MCP non trouvé: $TOKEN_FILE"
    exit 1
fi

# Lire le token
MCP_TOKEN=$(sudo cat "$TOKEN_FILE" 2>/dev/null | tr -d '[:space:]')

if [ -z "$MCP_TOKEN" ]; then
    log_error "Token vide ou impossible à lire"
    exit 1
fi

log_info "Token MCP récupéré (${#MCP_TOKEN} caractères)"

# Vérifier que le service MCP est accessible
if ! ss -tlnp | grep -q ":$MCP_PORT "; then
    log_error "Le port $MCP_PORT n'est pas en écoute"
    log_info "Vérifiez que le service MCP est démarré:"
    log_info "  sudo systemctl status essensys-mcp"
    exit 1
fi

log_info "Port $MCP_PORT en écoute ✓"

# Vérifier que Redis est accessible
if ! redis-cli ping > /dev/null 2>&1; then
    log_error "Redis n'est pas accessible"
    exit 1
fi

log_info "Redis accessible ✓"

# Configuration de la lumière
# "chevet chambre petit 3" correspond à:
# - Index 621: Scenario_Allumer_CHB_LSB (Allumer lumières Chambres LSB)
# - Bit 6 (valeur 64): Lampe de la petite chambre 3
LIGHT_INDEX=621
LIGHT_VALUE=64
LIGHT_COMMAND="[{\"k\":${LIGHT_INDEX},\"v\":\"${LIGHT_VALUE}\"}]"

log_info ""
log_info "=========================================="
log_info "Commande: Allumer 'chevet chambre petit 3'"
log_info "Index: $LIGHT_INDEX"
log_info "Valeur: $LIGHT_VALUE (bit 6)"
log_info "=========================================="
log_info ""

# Note: Le protocole MCP SSE nécessite normalement une session SSE active
# Cependant, le serveur peut accepter les requêtes POST /messages même sans session
# Si vous obtenez "Missing sessionId", cela signifie que le serveur fonctionne
# mais nécessite un client MCP complet pour établir la session SSE

log_info "Envoi de la commande via MCP..."

# Envoyer la commande send_order
SEND_ORDER_RESPONSE=$(curl -k -s -w "\n%{http_code}" \
  -H "Authorization: Bearer $MCP_TOKEN" \
  -H "Content-Type: application/json" \
  -X POST \
  -d "{
    \"jsonrpc\": \"2.0\",
    \"id\": 1,
    \"method\": \"tools/call\",
    \"params\": {
      \"name\": \"send_order\",
      \"arguments\": {
        \"params_json\": \"$LIGHT_COMMAND\"
      }
    }
  }" \
  "$MCP_URL" 2>&1)

HTTP_CODE=$(echo "$SEND_ORDER_RESPONSE" | tail -1)
BODY=$(echo "$SEND_ORDER_RESPONSE" | head -n -1)

log_info ""
log_info "Réponse du serveur MCP:"
log_info "Code HTTP: $HTTP_CODE"

if [ "$HTTP_CODE" = "200" ]; then
    log_info "✓ Commande envoyée avec succès!"
    echo "$BODY" | jq . 2>/dev/null || echo "$BODY"
    
    # Extraire le GUID si présent
    GUID=$(echo "$BODY" | jq -r '.result.text // empty' 2>/dev/null | grep -oP 'GUID \K[^\s]+' || echo "")
    
    if [ -n "$GUID" ]; then
        log_info "GUID de l'action: $GUID"
    fi
    
elif [ "$HTTP_CODE" = "400" ] && echo "$BODY" | grep -q "Missing sessionId"; then
    log_warn "⚠ Erreur: Missing sessionId"
    log_info ""
    log_info "Le protocole MCP SSE nécessite une session SSE active."
    log_info "Cependant, le serveur peut fonctionner différemment."
    log_info ""
    log_info "Vérification dans Redis si la commande a été traitée..."
    
    # Vérifier quand même dans Redis
    LAST_ACTION=$(redis-cli LRANGE "essensys:global:actions" -1 -1 2>/dev/null | tail -1)
    if [ -n "$LAST_ACTION" ] && echo "$LAST_ACTION" | grep -q "\"k\":$LIGHT_INDEX"; then
        log_info "✓ Commande trouvée dans Redis malgré l'erreur!"
        log_info "La commande a peut-être été traitée."
    else
        log_warn "Commande non trouvée dans Redis"
        log_info ""
        log_info "Pour utiliser correctement le protocole MCP SSE, utilisez un client MCP complet"
        log_info "comme MCP Inspector ou un client personnalisé qui établit une session SSE."
    fi
    
    echo "$BODY" | jq . 2>/dev/null || echo "$BODY"
    
elif [ "$HTTP_CODE" = "400" ]; then
    log_error "✗ Erreur 400: Requête invalide"
    echo "$BODY" | jq . 2>/dev/null || echo "$BODY"
    exit 1
    
else
    log_error "✗ Erreur HTTP: $HTTP_CODE"
    echo "$BODY"
    exit 1
fi

# Vérifier dans Redis que la commande a été ajoutée à la queue
log_info ""
log_info "Vérification dans Redis..."

QUEUE_SIZE=$(redis-cli LLEN "essensys:global:actions" 2>/dev/null || echo "0")
log_info "Taille de la queue: $QUEUE_SIZE actions"

if [ "$QUEUE_SIZE" -gt 0 ]; then
    log_info ""
    log_info "Dernières actions dans la queue:"
    redis-cli LRANGE "essensys:global:actions" -5 -1 2>/dev/null | while read -r action; do
        if echo "$action" | grep -q "\"k\":$LIGHT_INDEX"; then
            log_info "✓ Action trouvée:"
            echo "$action" | jq . 2>/dev/null || echo "$action"
        fi
    done
else
    log_warn "Aucune action dans la queue Redis"
fi

log_info ""
log_info "=========================================="
log_info "Test terminé!"
log_info ""
log_info "Pour vérifier que la commande a été traitée:"
log_info "  redis-cli LRANGE essensys:global:actions 0 -1"
log_info ""
log_info "Pour voir les logs du backend qui traite les commandes:"
log_info "  sudo journalctl -u essensys-backend -f"
log_info ""
log_info "Pour voir les logs du serveur MCP:"
log_info "  sudo journalctl -u essensys-mcp -f"
log_info ""
