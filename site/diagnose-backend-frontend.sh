#!/bin/bash
# Script de diagnostic pour le backend et frontend Essensys

set -e

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

echo "=========================================="
echo "Diagnostic Backend et Frontend Essensys"
echo "=========================================="
echo ""

# 1. Vérifier le service backend
echo "1. Vérification du service backend..."
if systemctl is-active --quiet essensys-backend; then
    log_info "✓ Service essensys-backend actif"
    BACKEND_ACTIVE=true
else
    log_error "✗ Service essensys-backend inactif"
    BACKEND_ACTIVE=false
fi

# Afficher le statut détaillé
echo ""
log_info "Statut détaillé du backend:"
systemctl status essensys-backend --no-pager -l | head -15 || true
echo ""

# 2. Vérifier le service frontend (nginx)
echo "2. Vérification du service frontend (nginx)..."
if systemctl is-active --quiet nginx; then
    log_info "✓ Service nginx actif"
    NGINX_ACTIVE=true
else
    log_error "✗ Service nginx inactif"
    NGINX_ACTIVE=false
fi

# Afficher le statut détaillé
echo ""
log_info "Statut détaillé de nginx:"
systemctl status nginx --no-pager -l | head -15 || true
echo ""

# 3. Vérifier les ports
echo "3. Vérification des ports..."

# Port backend (7070)
if ss -tlnp | grep -q ":7070 "; then
    log_info "✓ Port 7070 (backend) en écoute"
    ss -tlnp | grep ":7070 "
else
    log_error "✗ Port 7070 (backend) non en écoute"
fi
echo ""

# Port nginx (80)
if ss -tlnp | grep -q ":80 "; then
    log_info "✓ Port 80 (nginx) en écoute"
    ss -tlnp | grep ":80 "
else
    log_error "✗ Port 80 (nginx) non en écoute"
fi
echo ""

# Port nginx frontend interne (9090)
if ss -tlnp | grep -q ":9090 "; then
    log_info "✓ Port 9090 (frontend interne) en écoute"
    ss -tlnp | grep ":9090 "
else
    log_warn "⚠ Port 9090 (frontend interne) non en écoute"
fi
echo ""

# 4. Vérifier les binaires
echo "4. Vérification des binaires..."

# Backend
if [ -f "/opt/essensys/backend/server" ]; then
    log_info "✓ Binaire backend existe: /opt/essensys/backend/server"
    ls -lh /opt/essensys/backend/server
    if [ -x "/opt/essensys/backend/server" ]; then
        log_info "✓ Binaire backend exécutable"
    else
        log_error "✗ Binaire backend non exécutable"
    fi
else
    log_error "✗ Binaire backend non trouvé: /opt/essensys/backend/server"
fi
echo ""

# Frontend dist
if [ -d "/opt/essensys/frontend/dist" ]; then
    log_info "✓ Répertoire frontend dist existe: /opt/essensys/frontend/dist"
    DIST_SIZE=$(du -sh /opt/essensys/frontend/dist 2>/dev/null | cut -f1 || echo "0")
    log_info "  Taille: $DIST_SIZE"
    FILE_COUNT=$(find /opt/essensys/frontend/dist -type f 2>/dev/null | wc -l || echo "0")
    log_info "  Nombre de fichiers: $FILE_COUNT"
    if [ "$FILE_COUNT" -eq 0 ]; then
        log_error "✗ Répertoire dist vide!"
    fi
else
    log_error "✗ Répertoire frontend dist non trouvé: /opt/essensys/frontend/dist"
fi
echo ""

# 5. Vérifier Redis (dépendance backend)
echo "5. Vérification de Redis..."
if systemctl is-active --quiet redis-server; then
    log_info "✓ Service redis-server actif"
    if redis-cli ping > /dev/null 2>&1; then
        log_info "✓ Redis répond (PONG)"
    else
        log_error "✗ Redis ne répond pas"
    fi
else
    log_error "✗ Service redis-server inactif"
fi
echo ""

# 6. Vérifier les logs récents
echo "6. Dernières erreurs dans les logs..."

# Logs backend
log_info "Logs backend (dernières 10 lignes):"
if [ "$BACKEND_ACTIVE" = true ]; then
    journalctl -u essensys-backend -n 10 --no-pager 2>/dev/null | tail -5 || echo "  Aucun log disponible"
else
    log_warn "Service inactif, vérification des logs de démarrage..."
    journalctl -u essensys-backend -n 20 --no-pager 2>/dev/null | grep -i "error\|fatal\|failed" | tail -5 || echo "  Aucune erreur récente"
fi
echo ""

# Logs nginx
log_info "Logs nginx (dernières erreurs):"
if [ -f "/var/log/nginx/error.log" ]; then
    tail -5 /var/log/nginx/error.log 2>/dev/null || echo "  Aucune erreur récente"
else
    echo "  Fichier de log non trouvé"
fi
echo ""

# 7. Vérifier la configuration
echo "7. Vérification de la configuration..."

# Configuration backend
if [ -f "/opt/essensys/backend/config.yaml" ]; then
    log_info "✓ Configuration backend existe"
    BACKEND_PORT=$(grep -E "^[[:space:]]*port:" /opt/essensys/backend/config.yaml 2>/dev/null | awk '{print $2}' || echo "7070")
    log_info "  Port configuré: $BACKEND_PORT"
else
    log_warn "⚠ Configuration backend non trouvée: /opt/essensys/backend/config.yaml"
fi
echo ""

# Configuration nginx
if nginx -t > /dev/null 2>&1; then
    log_info "✓ Configuration nginx valide"
else
    log_error "✗ Configuration nginx invalide"
    nginx -t 2>&1 | head -10
fi
echo ""

# 8. Test de connectivité
echo "8. Test de connectivité..."

# Test backend
log_info "Test connexion backend (port 7070)..."
if curl -s --max-time 2 http://localhost:7070/health > /dev/null 2>&1; then
    log_info "✓ Backend répond sur /health"
    HEALTH_RESPONSE=$(curl -s --max-time 2 http://localhost:7070/health 2>/dev/null || echo "")
    log_info "  Réponse: $HEALTH_RESPONSE"
else
    log_error "✗ Backend ne répond pas sur /health"
fi
echo ""

# Test frontend
log_info "Test connexion frontend (port 80)..."
if curl -s --max-time 2 http://localhost/ > /dev/null 2>&1; then
    HTTP_CODE=$(curl -s -w "%{http_code}" --max-time 2 http://localhost/ -o /dev/null 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ]; then
        log_info "✓ Frontend répond (HTTP 200)"
    else
        log_warn "⚠ Frontend répond avec code HTTP $HTTP_CODE"
    fi
else
    log_error "✗ Frontend ne répond pas"
fi
echo ""

# 9. Résumé et recommandations
echo "=========================================="
echo "Résumé"
echo "=========================================="
echo ""

if [ "$BACKEND_ACTIVE" = true ] && [ "$NGINX_ACTIVE" = true ]; then
    log_info "Services actifs: Backend ✓, Frontend ✓"
else
    log_error "Services inactifs détectés!"
    echo ""
    log_info "Commandes pour redémarrer:"
    if [ "$BACKEND_ACTIVE" = false ]; then
        echo "  sudo systemctl restart essensys-backend"
        echo "  sudo systemctl status essensys-backend"
    fi
    if [ "$NGINX_ACTIVE" = false ]; then
        echo "  sudo systemctl restart nginx"
        echo "  sudo systemctl status nginx"
    fi
fi

echo ""
log_info "Pour voir les logs en temps réel:"
echo "  Backend: sudo journalctl -u essensys-backend -f"
echo "  Frontend: sudo journalctl -u nginx -f"
echo ""
log_info "Pour voir les logs complets:"
echo "  Backend: sudo journalctl -u essensys-backend -n 100"
echo "  Frontend: sudo tail -f /var/log/nginx/error.log"
echo ""
