# Guide de débogage MCP (Model Context Protocol)

Ce guide vous aide à diagnostiquer et résoudre les problèmes avec le serveur MCP Essensys.

## 1. Vérifier le statut du service

```bash
# Vérifier si le service est actif
sudo systemctl status essensys-mcp

# Voir les logs en temps réel
sudo journalctl -u essensys-mcp -f

# Voir les dernières lignes de logs
sudo journalctl -u essensys-mcp -n 50
```

## 2. Vérifier que le binaire existe et fonctionne

```bash
# Vérifier que le binaire est installé
ls -lh /usr/local/bin/essensys-mcp

# Tester le binaire manuellement (en mode stdio pour test)
sudo -u essensys /usr/local/bin/essensys-mcp -mode stdio

# Vérifier la version et les options
sudo -u essensys /usr/local/bin/essensys-mcp -h
```

## 3. Vérifier la configuration

```bash
# Vérifier que le token existe
sudo cat /etc/essensys/mcp.token

# Vérifier les permissions du token
ls -l /etc/essensys/mcp.token

# Vérifier le fichier de service systemd
cat /etc/systemd/system/essensys-mcp.service
```

## 4. Vérifier Redis (dépendance requise)

```bash
# Vérifier que Redis est actif
sudo systemctl status redis-server

# Tester la connexion Redis
redis-cli ping

# Vérifier les clés Essensys dans Redis
redis-cli KEYS "essensys:*"
```

## 5. Tester la connexion SSE (Server-Sent Events)

```bash
# Récupérer le token
MCP_TOKEN=$(sudo cat /etc/essensys/mcp.token)

# Tester la connexion SSE avec curl
curl -k -N \
  -H "Authorization: Bearer $MCP_TOKEN" \
  -H "Accept: text/event-stream" \
  http://localhost:8080/sse

# Tester l'endpoint /messages
curl -k \
  -H "Authorization: Bearer $MCP_TOKEN" \
  -H "Content-Type: application/json" \
  -X POST \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test-client","version":"1.0.0"}}}' \
  http://localhost:8080/messages
```

## 6. Vérifier les ports et la connectivité

```bash
# Vérifier que le port 8080 est en écoute
sudo netstat -tlnp | grep 8080
# ou
sudo ss -tlnp | grep 8080

# Vérifier depuis l'extérieur (si accessible)
curl -k -I http://localhost:8080/sse
```

## 7. Vérifier les logs détaillés

```bash
# Logs avec plus de détails
sudo journalctl -u essensys-mcp -n 100 --no-pager

# Logs depuis une heure spécifique
sudo journalctl -u essensys-mcp --since "1 hour ago"

# Logs avec timestamps
sudo journalctl -u essensys-mcp -o short-precise
```

## 8. Redémarrer le service

```bash
# Redémarrer le service
sudo systemctl restart essensys-mcp

# Vérifier immédiatement après redémarrage
sudo systemctl status essensys-mcp
sudo journalctl -u essensys-mcp -n 20
```

## 9. Vérifier les permissions et l'utilisateur

```bash
# Vérifier que l'utilisateur essensys existe
id essensys

# Vérifier les permissions du répertoire de travail
ls -ld /home/essensys/essensys-server-backend/cmd/mcp-server

# Vérifier les permissions du binaire
ls -l /usr/local/bin/essensys-mcp
```

## 10. Test de compilation manuelle

Si le service ne démarre pas, tester la compilation manuelle :

```bash
# Se connecter en tant qu'utilisateur essensys
sudo -u essensys bash

# Aller dans le répertoire source
cd /home/essensys/essensys-server-backend/cmd/mcp-server

# Vérifier que le code est à jour
git status
git log --oneline -5

# Vérifier la ligne 283 du fichier main.go
sed -n '280,285p' main.go

# Compiler manuellement
/usr/local/go/bin/go build -o essensys-mcp

# Tester le binaire compilé
./essensys-mcp -mode sse -port 8080 -token $(cat /etc/essensys/mcp.token)
```

## 11. Vérifier les erreurs de compilation

Si la compilation échoue dans Ansible :

```bash
# Vérifier les logs Ansible
tail -f /var/log/ansible.log

# Vérifier le code source sur le Raspberry Pi
cd /home/essensys/essensys-server-backend
git log --oneline -5
git show HEAD:cmd/mcp-server/main.go | sed -n '280,285p'
```

## 12. Test avec MCP Inspector (optionnel)

Si vous avez installé MCP Inspector :

```bash
# Installer MCP Inspector
npm install -g @modelcontextprotocol/inspector

# Tester avec le serveur SSE
mcp-inspect sse http://localhost:8080/sse \
  --header "Authorization: Bearer $MCP_TOKEN"
```

## 13. Vérifier la configuration du firewall

```bash
# Vérifier les règles iptables
sudo iptables -L -n | grep 8080

# Vérifier ufw si activé
sudo ufw status | grep 8080
```

## 14. Problèmes courants et solutions

### Le service ne démarre pas

```bash
# Vérifier les erreurs de démarrage
sudo systemctl status essensys-mcp
sudo journalctl -u essensys-mcp -n 50

# Vérifier que Redis est accessible
redis-cli ping

# Vérifier que le port n'est pas déjà utilisé
sudo lsof -i :8080
```

### Erreur de compilation

```bash
# Vérifier la version de Go
/usr/local/go/bin/go version

# Vérifier que le code est à jour
cd /home/essensys/essensys-server-backend
git fetch origin
git log --oneline origin/V.1.2.2 -5
```

### Erreur d'authentification

```bash
# Vérifier le token
sudo cat /etc/essensys/mcp.token

# Régénérer le token si nécessaire
sudo openssl rand -hex 32 > /etc/essensys/mcp.token
sudo chmod 600 /etc/essensys/mcp.token
sudo systemctl restart essensys-mcp
```

### Redis non accessible

```bash
# Démarrer Redis si arrêté
sudo systemctl start redis-server
sudo systemctl enable redis-server

# Vérifier la configuration Redis
sudo cat /etc/redis/redis.conf | grep -E "^bind|^port"
```

## 15. Commandes de diagnostic rapide

Script de diagnostic complet :

```bash
#!/bin/bash
echo "=== Diagnostic MCP ==="
echo ""
echo "1. Statut du service:"
sudo systemctl status essensys-mcp --no-pager -l | head -10
echo ""
echo "2. Binaire installé:"
ls -lh /usr/local/bin/essensys-mcp 2>/dev/null || echo "Binaire non trouvé"
echo ""
echo "3. Token configuré:"
[ -f /etc/essensys/mcp.token ] && echo "Token existe" || echo "Token manquant"
echo ""
echo "4. Redis actif:"
sudo systemctl is-active redis-server && echo "Redis actif" || echo "Redis inactif"
echo ""
echo "5. Port en écoute:"
sudo ss -tlnp | grep 8080 || echo "Port 8080 non en écoute"
echo ""
echo "6. Dernières erreurs:"
sudo journalctl -u essensys-mcp -n 10 --no-pager | grep -i error || echo "Aucune erreur récente"
```

## 16. Logs à surveiller

Surveillez ces messages dans les logs :

- `Starting MCP SSE server` : Le serveur démarre correctement
- `Blocked access from non-private IP` : Tentative d'accès depuis une IP publique (normal)
- `Unauthorized: Missing Authorization header` : Token manquant ou invalide
- `Redis error` : Problème de connexion à Redis
- `too many arguments in call to mcp.Required` : Erreur de compilation (code non à jour)

## 17. Contact et support

Si le problème persiste après avoir suivi ce guide :

1. Collecter les logs complets : `sudo journalctl -u essensys-mcp > mcp-logs.txt`
2. Vérifier la version du code : `cd /home/essensys/essensys-server-backend && git log -1`
3. Vérifier la version de Go : `/usr/local/go/bin/go version`
4. Vérifier la version d'Ansible utilisée pour l'installation
