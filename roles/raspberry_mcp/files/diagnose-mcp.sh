#!/bin/bash
# Script de diagnostic pour le serveur MCP Essensys

set -e

echo "=========================================="
echo "Diagnostic Essensys MCP Server"
echo "=========================================="
echo ""

# 1. Vérifier le statut du service
echo "1. Statut du service:"
if systemctl is-active --quiet essensys-mcp; then
    echo "   ✓ Service actif"
elif systemctl is-failed --quiet essensys-mcp; then
    echo "   ✗ Service en échec"
    echo ""
    echo "   Dernières erreurs:"
    sudo journalctl -u essensys-mcp -n 20 --no-pager | tail -10
else
    echo "   ⚠ Service inactif"
fi
echo ""

# 2. Vérifier le binaire
echo "2. Binaire MCP:"
if [ -f /usr/local/bin/essensys-mcp ]; then
    echo "   ✓ Binaire existe: $(ls -lh /usr/local/bin/essensys-mcp | awk '{print $5, $9}')"
    if [ -x /usr/local/bin/essensys-mcp ]; then
        echo "   ✓ Binaire exécutable"
    else
        echo "   ✗ Binaire NON exécutable!"
        echo "   Correction: sudo chmod +x /usr/local/bin/essensys-mcp"
    fi
else
    echo "   ✗ Binaire non trouvé: /usr/local/bin/essensys-mcp"
fi
echo ""

# 3. Tester le binaire manuellement
echo "3. Test du binaire:"
if [ -f /usr/local/bin/essensys-mcp ] && [ -x /usr/local/bin/essensys-mcp ]; then
    echo "   Test avec -h (aide):"
    /usr/local/bin/essensys-mcp -h 2>&1 | head -5 || echo "   ✗ Erreur lors de l'exécution"
fi
echo ""

# 4. Vérifier le token
echo "4. Token d'authentification:"
if [ -f /etc/essensys/mcp.token ]; then
    TOKEN=$(cat /etc/essensys/mcp.token | tr -d '[:space:]')
    if [ -n "$TOKEN" ]; then
        echo "   ✓ Token existe (${#TOKEN} caractères)"
        echo "   Token: ${TOKEN:0:20}..."
    else
        echo "   ✗ Token vide!"
    fi
    echo "   Permissions: $(ls -l /etc/essensys/mcp.token | awk '{print $1, $3, $4}')"
else
    echo "   ✗ Token manquant: /etc/essensys/mcp.token"
    echo "   Génération: sudo openssl rand -hex 32 > /etc/essensys/mcp.token"
fi
echo ""

# 5. Vérifier Redis
echo "5. Redis:"
if systemctl is-active --quiet redis-server; then
    echo "   ✓ Service Redis actif"
    if redis-cli ping > /dev/null 2>&1; then
        echo "   ✓ Redis accessible"
    else
        echo "   ✗ Redis non accessible (ping échoue)"
    fi
else
    echo "   ✗ Service Redis inactif"
    echo "   Démarrage: sudo systemctl start redis-server"
fi
echo ""

# 6. Vérifier le port
echo "6. Port 8080:"
if ss -tlnp | grep -q ":8080"; then
    echo "   ⚠ Port 8080 déjà utilisé:"
    ss -tlnp | grep ":8080"
    echo "   Vérifiez si un autre processus utilise le port"
else
    echo "   ✓ Port 8080 libre"
fi
echo ""

# 7. Vérifier le fichier de service systemd
echo "7. Configuration systemd:"
if [ -f /etc/systemd/system/essensys-mcp.service ]; then
    echo "   ✓ Fichier de service existe"
    echo "   Contenu ExecStart:"
    grep "^ExecStart" /etc/systemd/system/essensys-mcp.service | sed 's/^/   /'
    echo ""
    echo "   Vérification de la syntaxe:"
    if systemd-analyze verify essensys-mcp.service 2>&1; then
        echo "   ✓ Syntaxe valide"
    else
        echo "   ✗ Erreur de syntaxe dans le fichier de service"
    fi
else
    echo "   ✗ Fichier de service manquant"
fi
echo ""

# 8. Test manuel du binaire avec le token
echo "8. Test manuel du binaire:"
if [ -f /etc/essensys/mcp.token ] && [ -f /usr/local/bin/essensys-mcp ]; then
    TOKEN=$(cat /etc/essensys/mcp.token | tr -d '[:space:]')
    echo "   Tentative de démarrage manuel (timeout 3s)..."
    timeout 3 /usr/local/bin/essensys-mcp -mode sse -port 8080 -token "$TOKEN" 2>&1 | head -5 || {
        EXIT_CODE=$?
        if [ $EXIT_CODE -eq 124 ]; then
            echo "   ✓ Binaire démarre (arrêté après timeout)"
        else
            echo "   ✗ Erreur lors du démarrage (code: $EXIT_CODE)"
            echo "   Essayez manuellement:"
            echo "   sudo /usr/local/bin/essensys-mcp -mode sse -port 8080 -token \$(cat /etc/essensys/mcp.token)"
        fi
    }
else
    echo "   ⚠ Impossible de tester (binaire ou token manquant)"
fi
echo ""

# 9. Vérifier les logs détaillés
echo "9. Derniers logs du service:"
echo "   (20 dernières lignes)"
sudo journalctl -u essensys-mcp -n 20 --no-pager | sed 's/^/   /'
echo ""

# 10. Recommandations
echo "=========================================="
echo "Recommandations:"
echo "=========================================="

if ! systemctl is-active --quiet essensys-mcp; then
    echo ""
    echo "Pour redémarrer le service:"
    echo "  sudo systemctl restart essensys-mcp"
    echo "  sudo systemctl status essensys-mcp"
    echo ""
    echo "Pour voir les logs en temps réel:"
    echo "  sudo journalctl -u essensys-mcp -f"
    echo ""
fi

if [ ! -f /usr/local/bin/essensys-mcp ]; then
    echo "Le binaire est manquant. Relancez le playbook Ansible:"
    echo "  cd /opt/essensys-ansible"
    echo "  sudo ansible-playbook -i inventory install.raspberrypi.yml"
    echo ""
fi

if ! systemctl is-active --quiet redis-server; then
    echo "Redis n'est pas actif. Démarrez-le:"
    echo "  sudo systemctl start redis-server"
    echo "  sudo systemctl enable redis-server"
    echo ""
fi

echo "Pour plus d'informations, consultez:"
echo "  /opt/essensys-ansible/docs/mcp-debug.md"
echo ""
