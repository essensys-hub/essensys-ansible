#!/bin/bash
# Script de test MCP pour allumer la lumière "chevet chambre petit 3"

set -e

# Configuration
MCP_URL="http://localhost:8083/messages"
TOKEN_FILE="/etc/essensys/mcp.token"

# Couleurs pour l'affichage
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
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

# Vérifier que le token existe
if [ ! -f "$TOKEN_FILE" ]; then
    log_error "Token MCP non trouvé: $TOKEN_FILE"
    exit 1
fi

# Lire le token
MCP_TOKEN=$(sudo cat "$TOKEN_FILE" | tr -d '[:space:]')

if [ -z "$MCP_TOKEN" ]; then
    log_error "Token vide"
    exit 1
fi

log_info "Token MCP récupéré (${#MCP_TOKEN} caractères)"

# Vérifier que le service MCP est actif
if ! systemctl is-active --quiet essensys-mcp; then
    log_warn "Le service essensys-mcp n'est pas actif"
    log_info "Démarrage du service..."
    sudo systemctl start essensys-mcp
    sleep 2
fi

# Vérifier que Redis est accessible
if ! redis-cli ping > /dev/null 2>&1; then
    log_error "Redis n'est pas accessible"
    exit 1
fi

log_info "Redis accessible"

# Test 1: Initialiser la connexion MCP
log_info "Test 1: Initialisation de la connexion MCP..."
INIT_RESPONSE=$(curl -k -s \
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
        "name": "test-light-client",
        "version": "1.0.0"
      }
    }
  }' \
  "$MCP_URL")

if echo "$INIT_RESPONSE" | grep -q '"result"'; then
    log_info "✓ Connexion MCP initialisée"
else
    log_error "✗ Échec de l'initialisation"
    echo "$INIT_RESPONSE" | jq . 2>/dev/null || echo "$INIT_RESPONSE"
    exit 1
fi

# Test 2: Lister les outils disponibles
log_info "Test 2: Liste des outils disponibles..."
TOOLS_RESPONSE=$(curl -k -s \
  -H "Authorization: Bearer $MCP_TOKEN" \
  -H "Content-Type: application/json" \
  -X POST \
  -d '{
    "jsonrpc": "2.0",
    "id": 2,
    "method": "tools/list"
  }' \
  "$MCP_URL")

if echo "$TOOLS_RESPONSE" | grep -q "send_order"; then
    log_info "✓ Outil send_order disponible"
else
    log_error "✗ Outil send_order non trouvé"
    echo "$TOOLS_RESPONSE" | jq . 2>/dev/null || echo "$TOOLS_RESPONSE"
    exit 1
fi

# Test 3: Envoyer la commande pour allumer la lumière
# "chevet chambre petit 3" correspond à:
# D'après test_chb3.py:
# - Index 613: Allumer Lumières CHB (LSB) - Scenario_Allumer_CHB_LSB (Offset 21)
# - Bit 6 (valeur 64): Lampe de la petite chambre 3
# - Index 590: Trigger scenario (obligatoire, valeur "1")
# Note: Le backend génère automatiquement le bloc complet (605-622) si un index lumière est présent
log_info "Test 3: Envoi de la commande pour allumer 'chevet chambre petit 3'..."

# Commande pour allumer la lampe de la petite chambre 3
# Format ExchangeKV: [{"k": index, "v": "valeur"}]
# Index 613 avec valeur 64 (bit 6) pour allumer la petite chambre 3
# Le backend ajoutera automatiquement l'index 590 et complétera le bloc 605-622
LIGHT_COMMAND='[{"k":613,"v":"64"}]'

log_info "Commande: $LIGHT_COMMAND"
log_warn "NOTE: Vous devrez peut-être adapter l'index (k) et la valeur (v) selon votre configuration"

SEND_ORDER_RESPONSE=$(curl -k -s \
  -H "Authorization: Bearer $MCP_TOKEN" \
  -H "Content-Type: application/json" \
  -X POST \
  -d "{
    \"jsonrpc\": \"2.0\",
    \"id\": 3,
    \"method\": \"tools/call\",
    \"params\": {
      \"name\": \"send_order\",
      \"arguments\": {
        \"params_json\": \"$LIGHT_COMMAND\"
      }
    }
  }" \
  "$MCP_URL")

echo ""
log_info "Réponse du serveur MCP:"
echo "$SEND_ORDER_RESPONSE" | jq . 2>/dev/null || echo "$SEND_ORDER_RESPONSE"
echo ""

if echo "$SEND_ORDER_RESPONSE" | grep -q '"error"'; then
    log_error "✗ Erreur lors de l'envoi de la commande"
    exit 1
elif echo "$SEND_ORDER_RESPONSE" | grep -q '"result"'; then
    log_info "✓ Commande envoyée avec succès"
    
    # Vérifier dans Redis que la commande a été ajoutée à la queue
    log_info "Vérification dans Redis..."
    LAST_ACTION=$(redis-cli LRANGE "essensys:global:actions" -1 -1 2>/dev/null | tail -1)
    if [ -n "$LAST_ACTION" ]; then
        log_info "✓ Dernière action dans la queue:"
        echo "$LAST_ACTION" | jq . 2>/dev/null || echo "$LAST_ACTION"
    else
        log_warn "Aucune action trouvée dans la queue Redis"
    fi
else
    log_warn "Réponse inattendue du serveur"
fi

echo ""
log_info "Test terminé!"
log_info ""
log_info "Pour vérifier que la commande a été traitée:"
log_info "  redis-cli LRANGE essensys:global:actions 0 -1"
log_info ""
log_info "Pour voir les logs du backend qui traite les commandes:"
log_info "  sudo journalctl -u essensys-backend -f"
