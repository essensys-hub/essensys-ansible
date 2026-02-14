#!/bin/bash
# Script de vérification de la configuration des ports Essensys
# Vérifie que le port 80 local et le port 443 WAN sont correctement configurés

set -e

echo "=========================================="
echo "Vérification de la configuration Essensys"
echo "=========================================="
echo ""

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

ERRORS=0
WARNINGS=0

# Fonction pour vérifier un port
check_port() {
    local port=$1
    local service=$2
    local required=$3
    
    if sudo ss -tlnp | grep -q ":${port} "; then
        echo -e "${GREEN}✓${NC} Port ${port} : ${service} est actif"
        return 0
    else
        if [ "$required" = "required" ]; then
            echo -e "${RED}✗${NC} Port ${port} : ${service} n'est PAS actif (OBLIGATOIRE)"
            ERRORS=$((ERRORS + 1))
            return 1
        else
            echo -e "${YELLOW}⚠${NC} Port ${port} : ${service} n'est pas actif (optionnel)"
            WARNINGS=$((WARNINGS + 1))
            return 0
        fi
    fi
}

# Fonction pour vérifier qu'un port n'est PAS utilisé par un service
check_port_not_used() {
    local port=$1
    local service=$2
    
    if sudo ss -tlnp | grep ":${port} " | grep -q "${service}"; then
        echo -e "${RED}✗${NC} Port ${port} : ${service} ne devrait PAS écouter sur ce port"
        ERRORS=$((ERRORS + 1))
        return 1
    else
        echo -e "${GREEN}✓${NC} Port ${port} : ${service} n'écoute pas sur ce port (correct)"
        return 0
    fi
}

echo "1. Vérification des ports obligatoires"
echo "----------------------------------------"

# Port 80 : Nginx (obligatoire pour armoires Essensys)
check_port 80 "Nginx" "required"

# Port 443 : Traefik (obligatoire pour WAN HTTPS)
check_port 443 "Traefik" "required"

# Port 7070 : Backend Essensys (obligatoire)
check_port 7070 "Backend Essensys" "required"

# Port 9090 : Frontend interne (obligatoire pour Traefik)
check_port 9090 "Nginx (frontend interne)" "required"

echo ""
echo "2. Vérification des conflits"
echo "----------------------------------------"

# Traefik ne doit PAS écouter sur le port 80
if sudo ss -tlnp | grep ":80 " | grep -q "traefik"; then
    echo -e "${RED}✗${NC} Traefik écoute sur le port 80 (CONFLIT avec Nginx)"
    ERRORS=$((ERRORS + 1))
else
    echo -e "${GREEN}✓${NC} Traefik n'écoute pas sur le port 80 (correct)"
fi

# Nginx doit écouter sur le port 80
if sudo ss -tlnp | grep ":80 " | grep -q "nginx"; then
    echo -e "${GREEN}✓${NC} Nginx écoute sur le port 80 (correct)"
else
    echo -e "${RED}✗${NC} Nginx n'écoute pas sur le port 80 (OBLIGATOIRE)"
    ERRORS=$((ERRORS + 1))
fi

echo ""
echo "3. Vérification des services systemd"
echo "----------------------------------------"

check_service() {
    local service=$1
    local required=$2
    
    if systemctl is-active --quiet "$service"; then
        echo -e "${GREEN}✓${NC} Service ${service} est actif"
        return 0
    else
        if [ "$required" = "required" ]; then
            echo -e "${RED}✗${NC} Service ${service} n'est PAS actif (OBLIGATOIRE)"
            ERRORS=$((ERRORS + 1))
            return 1
        else
            echo -e "${YELLOW}⚠${NC} Service ${service} n'est pas actif (optionnel)"
            WARNINGS=$((WARNINGS + 1))
            return 0
        fi
    fi
}

check_service "nginx" "required"
check_service "traefik" "required"
check_service "essensys-backend" "required"

echo ""
echo "4. Tests de connectivité"
echo "----------------------------------------"

# Test port 80 local
if curl -s -o /dev/null -w "%{http_code}" http://localhost/ | grep -q "200\|301\|302"; then
    echo -e "${GREEN}✓${NC} Port 80 : Frontend accessible localement"
else
    echo -e "${RED}✗${NC} Port 80 : Frontend non accessible localement"
    ERRORS=$((ERRORS + 1))
fi

# Test API sur port 80
if curl -s -o /dev/null -w "%{http_code}" http://localhost/api/serverinfos | grep -q "200\|404"; then
    echo -e "${GREEN}✓${NC} Port 80 : API accessible localement"
else
    echo -e "${YELLOW}⚠${NC} Port 80 : API non accessible (peut être normal si backend non démarré)"
    WARNINGS=$((WARNINGS + 1))
fi

# Test backend direct
if curl -s -o /dev/null -w "%{http_code}" http://localhost:7070/health | grep -q "200"; then
    echo -e "${GREEN}✓${NC} Port 7070 : Backend accessible directement"
else
    echo -e "${YELLOW}⚠${NC} Port 7070 : Backend non accessible (peut être normal si backend non démarré)"
    WARNINGS=$((WARNINGS + 1))
fi

# Test frontend interne
if curl -s -o /dev/null -w "%{http_code}" http://localhost:9090/ | grep -q "200\|301\|302"; then
    echo -e "${GREEN}✓${NC} Port 9090 : Frontend interne accessible"
else
    echo -e "${RED}✗${NC} Port 9090 : Frontend interne non accessible"
    ERRORS=$((ERRORS + 1))
fi

echo ""
echo "5. Résumé"
echo "----------------------------------------"
echo ""

if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}✓ Configuration correcte !${NC}"
    if [ $WARNINGS -gt 0 ]; then
        echo -e "${YELLOW}⚠ ${WARNINGS} avertissement(s)${NC}"
    fi
    exit 0
else
    echo -e "${RED}✗ ${ERRORS} erreur(s) détectée(s)${NC}"
    if [ $WARNINGS -gt 0 ]; then
        echo -e "${YELLOW}⚠ ${WARNINGS} avertissement(s)${NC}"
    fi
    echo ""
    echo "Actions recommandées :"
    echo "1. Vérifier les logs : sudo journalctl -u nginx -u traefik -u essensys-backend"
    echo "2. Vérifier les configurations : sudo nginx -t"
    echo "3. Redémarrer les services si nécessaire"
    exit 1
fi
