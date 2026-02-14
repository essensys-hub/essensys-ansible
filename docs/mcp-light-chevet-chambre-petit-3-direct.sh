#!/bin/bash
# Script pour allumer la lumière "chevet chambre petit 3"
# Utilise directement Redis pour contourner le problème de sessionId MCP SSE

set -e

# Configuration
LIGHT_INDEX=621
LIGHT_VALUE=64
REDIS_KEY="essensys:global:actions"

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

# Vérifier que Redis est accessible
if ! redis-cli ping > /dev/null 2>&1; then
    log_error "Redis n'est pas accessible"
    log_info "Vérifiez que Redis est démarré: sudo systemctl status redis-server"
    exit 1
fi

log_info "Redis accessible ✓"

# Générer un GUID unique
GUID="mcp-direct-$(date +%s)-$$"

# Créer la commande JSON
LIGHT_COMMAND="[{\"k\":${LIGHT_INDEX},\"v\":\"${LIGHT_VALUE}\"}]"
ACTION_JSON="{\"guid\":\"${GUID}\",\"params\":${LIGHT_COMMAND}}"

log_info ""
log_info "=========================================="
log_info "Commande: Allumer 'chevet chambre petit 3'"
log_info "Index: $LIGHT_INDEX"
log_info "Valeur: $LIGHT_VALUE (bit 6)"
log_info "GUID: $GUID"
log_info "=========================================="
log_info ""

log_info "Ajout de la commande à la queue Redis..."

# Ajouter la commande à la queue Redis
if redis-cli RPUSH "$REDIS_KEY" "$ACTION_JSON" > /dev/null 2>&1; then
    log_info "✓ Commande ajoutée à la queue Redis avec succès!"
    
    # Vérifier que la commande est bien dans la queue
    QUEUE_SIZE=$(redis-cli LLEN "$REDIS_KEY" 2>/dev/null || echo "0")
    log_info "Taille de la queue: $QUEUE_SIZE actions"
    
    log_info ""
    log_info "Dernière action ajoutée:"
    LAST_ACTION=$(redis-cli LRANGE "$REDIS_KEY" -1 -1 2>/dev/null | tail -1)
    if [ -n "$LAST_ACTION" ]; then
        echo "$LAST_ACTION" | jq . 2>/dev/null || echo "$LAST_ACTION"
        
        # Vérifier que c'est bien notre commande
        if echo "$LAST_ACTION" | grep -q "\"guid\":\"$GUID\""; then
            log_info "✓ Commande confirmée dans Redis"
        fi
    fi
    
    log_info ""
    log_info "=========================================="
    log_info "Commande envoyée avec succès!"
    log_info ""
    log_info "La commande sera traitée par le backend Essensys."
    log_info "Le backend lit la queue Redis et envoie les commandes aux robots."
    log_info ""
    log_info "Pour vérifier que la commande a été traitée:"
    log_info "  redis-cli LRANGE $REDIS_KEY 0 -1"
    log_info ""
    log_info "Pour voir les logs du backend qui traite les commandes:"
    log_info "  sudo journalctl -u essensys-backend -f"
    log_info ""
    log_info "Pour voir toutes les actions dans Redis:"
    log_info "  redis-cli LRANGE $REDIS_KEY 0 -1 | jq ."
    log_info ""
    
else
    log_error "✗ Erreur lors de l'ajout de la commande à Redis"
    exit 1
fi
