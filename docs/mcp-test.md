# Guide de test du serveur MCP Essensys

Ce guide vous montre comment tester le serveur MCP après installation.

## Prérequis

- Le serveur MCP doit être installé et démarré
- Redis doit être actif
- Le token d'authentification doit être configuré

## 1. Vérifications de base

### Vérifier que le service est actif

```bash
sudo systemctl status essensys-mcp
```

Vous devriez voir `active (running)`.

### Vérifier que Redis fonctionne

```bash
redis-cli ping
```

Réponse attendue : `PONG`

### Vérifier que le port est en écoute

```bash
sudo ss -tlnp | grep 8080
```

Vous devriez voir quelque chose comme :
```
LISTEN 0 4096 *:8083 *:* users:(("essensys-mcp",pid=1234,fd=3))
```

## 2. Test de connexion SSE basique

### Récupérer le token

```bash
MCP_TOKEN=$(sudo cat /etc/essensys/mcp.token)
echo "Token: $MCP_TOKEN"
```

### Test de connexion SSE simple

```bash
curl -k -N \
  -H "Authorization: Bearer $MCP_TOKEN" \
  -H "Accept: text/event-stream" \
  http://localhost:8083/sse
```

Vous devriez voir des événements SSE qui arrivent. Appuyez sur `Ctrl+C` pour arrêter.

## 3. Test avec requête JSON-RPC

### Test d'initialisation

```bash
MCP_TOKEN=$(sudo cat /etc/essensys/mcp.token)

curl -k \
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
  http://localhost:8083/messages
```

Réponse attendue : Un JSON avec les informations du serveur MCP.

### Lister les outils disponibles

```bash
MCP_TOKEN=$(sudo cat /etc/essensys/mcp.token)

curl -k \
  -H "Authorization: Bearer $MCP_TOKEN" \
  -H "Content-Type: application/json" \
  -X POST \
  -d '{
    "jsonrpc": "2.0",
    "id": 2,
    "method": "tools/list"
  }' \
  http://localhost:8083/messages
```

Réponse attendue : Liste des outils MCP disponibles (read_exchange_table, read_exchange_value, set_exchange_value, send_order).

## 4. Test des outils MCP

### Test 1 : Lire la table d'échange complète

```bash
MCP_TOKEN=$(sudo cat /etc/essensys/mcp.token)

curl -k \
  -H "Authorization: Bearer $MCP_TOKEN" \
  -H "Content-Type: application/json" \
  -X POST \
  -d '{
    "jsonrpc": "2.0",
    "id": 3,
    "method": "tools/call",
    "params": {
      "name": "read_exchange_table",
      "arguments": {
        "client_id": "default"
      }
    }
  }' \
  http://localhost:8083/messages
```

### Test 2 : Lire une valeur spécifique de la table d'échange

```bash
MCP_TOKEN=$(sudo cat /etc/essensys/mcp.token)

curl -k \
  -H "Authorization: Bearer $MCP_TOKEN" \
  -H "Content-Type: application/json" \
  -X POST \
  -d '{
    "jsonrpc": "2.0",
    "id": 4,
    "method": "tools/call",
    "params": {
      "name": "read_exchange_value",
      "arguments": {
        "client_id": "default",
        "index": 1
      }
    }
  }' \
  http://localhost:8083/messages
```

### Test 3 : Écrire une valeur dans la table d'échange

```bash
MCP_TOKEN=$(sudo cat /etc/essensys/mcp.token)

curl -k \
  -H "Authorization: Bearer $MCP_TOKEN" \
  -H "Content-Type: application/json" \
  -X POST \
  -d '{
    "jsonrpc": "2.0",
    "id": 5,
    "method": "tools/call",
    "params": {
      "name": "set_exchange_value",
      "arguments": {
        "client_id": "default",
        "index": 1,
        "value": "test-value"
      }
    }
  }' \
  http://localhost:8083/messages
```

### Test 4 : Envoyer une commande (order)

```bash
MCP_TOKEN=$(sudo cat /etc/essensys/mcp.token)

curl -k \
  -H "Authorization: Bearer $MCP_TOKEN" \
  -H "Content-Type: application/json" \
  -X POST \
  -d '{
    "jsonrpc": "2.0",
    "id": 6,
    "method": "tools/call",
    "params": {
      "name": "send_order",
      "arguments": {
        "params_json": "[{\"k\":1,\"v\":\"test\"}]"
      }
    }
  }' \
  http://localhost:8083/messages
```

## 5. Test avec script Python (optionnel)

Créez un fichier `test_mcp.py` :

```python
#!/usr/bin/env python3
import requests
import json
import sys

# Configuration
MCP_URL = "http://localhost:8083/messages"
TOKEN_FILE = "/etc/essensys/mcp.token"

# Lire le token
try:
    with open(TOKEN_FILE, 'r') as f:
        token = f.read().strip()
except FileNotFoundError:
    print(f"Erreur: {TOKEN_FILE} non trouvé")
    sys.exit(1)

headers = {
    "Authorization": f"Bearer {token}",
    "Content-Type": "application/json"
}

# Test 1: Initialize
print("Test 1: Initialize...")
response = requests.post(
    MCP_URL,
    headers=headers,
    json={
        "jsonrpc": "2.0",
        "id": 1,
        "method": "initialize",
        "params": {
            "protocolVersion": "2024-11-05",
            "capabilities": {},
            "clientInfo": {"name": "test-client", "version": "1.0.0"}
        }
    },
    verify=False
)
print(f"Status: {response.status_code}")
print(f"Response: {json.dumps(response.json(), indent=2)}")
print()

# Test 2: List tools
print("Test 2: List tools...")
response = requests.post(
    MCP_URL,
    headers=headers,
    json={
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/list"
    },
    verify=False
)
print(f"Status: {response.status_code}")
print(f"Response: {json.dumps(response.json(), indent=2)}")
print()

# Test 3: Read exchange table
print("Test 3: Read exchange table...")
response = requests.post(
    MCP_URL,
    headers=headers,
    json={
        "jsonrpc": "2.0",
        "id": 3,
        "method": "tools/call",
        "params": {
            "name": "read_exchange_table",
            "arguments": {"client_id": "default"}
        }
    },
    verify=False
)
print(f"Status: {response.status_code}")
print(f"Response: {json.dumps(response.json(), indent=2)}")
print()

print("Tests terminés!")
```

Exécutez-le avec :
```bash
sudo python3 test_mcp.py
```

## 6. Test avec MCP Inspector (recommandé)

### Installation de MCP Inspector

```bash
npm install -g @modelcontextprotocol/inspector
```

### Test avec SSE

```bash
MCP_TOKEN=$(sudo cat /etc/essensys/mcp.token)

mcp-inspect sse http://localhost:8083/sse \
  --header "Authorization: Bearer $MCP_TOKEN"
```

Cela ouvre une interface web interactive pour tester les outils MCP.

## 7. Vérification des données Redis

### Vérifier que les données sont bien stockées dans Redis

```bash
# Voir toutes les clés Essensys
redis-cli KEYS "essensys:*"

# Voir le contenu de la table d'échange
redis-cli HGETALL "essensys:client:default:exchange"

# Voir la queue d'actions globales
redis-cli LRANGE "essensys:global:actions" 0 -1
```

## 8. Test de bout en bout

### Scénario complet : Écrire puis lire

```bash
MCP_TOKEN=$(sudo cat /etc/essensys/mcp.token)

# 1. Écrire une valeur
echo "Écriture d'une valeur..."
curl -k -s \
  -H "Authorization: Bearer $MCP_TOKEN" \
  -H "Content-Type: application/json" \
  -X POST \
  -d '{
    "jsonrpc": "2.0",
    "id": 10,
    "method": "tools/call",
    "params": {
      "name": "set_exchange_value",
      "arguments": {
        "client_id": "default",
        "index": 5,
        "value": "hello-world"
      }
    }
  }' \
  http://localhost:8083/messages | jq .

# 2. Lire la valeur
echo "Lecture de la valeur..."
curl -k -s \
  -H "Authorization: Bearer $MCP_TOKEN" \
  -H "Content-Type: application/json" \
  -X POST \
  -d '{
    "jsonrpc": "2.0",
    "id": 11,
    "method": "tools/call",
    "params": {
      "name": "read_exchange_value",
      "arguments": {
        "client_id": "default",
        "index": 5
      }
    }
  }' \
  http://localhost:8083/messages | jq .

# 3. Vérifier dans Redis directement
echo "Vérification dans Redis..."
redis-cli HGET "essensys:client:default:exchange" "5"
```

## 9. Test d'erreurs et sécurité

### Test sans token (devrait échouer)

```bash
curl -k \
  -H "Content-Type: application/json" \
  -X POST \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
  http://localhost:8083/messages
```

Réponse attendue : `401 Unauthorized`

### Test avec token invalide (devrait échouer)

```bash
curl -k \
  -H "Authorization: Bearer invalid-token" \
  -H "Content-Type: application/json" \
  -X POST \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
  http://localhost:8083/messages
```

Réponse attendue : `401 Unauthorized`

### Test depuis une IP publique (devrait être bloqué)

Si vous testez depuis une IP publique, l'accès devrait être refusé avec `403 Forbidden`.

## 10. Script de test automatisé

Créez un fichier `test_mcp.sh` :

```bash
#!/bin/bash

set -e

MCP_TOKEN=$(sudo cat /etc/essensys/mcp.token)
MCP_URL="http://localhost:8083/messages"

echo "=== Test du serveur MCP Essensys ==="
echo ""

# Test 1: Service actif
echo "1. Vérification du service..."
if systemctl is-active --quiet essensys-mcp; then
    echo "✓ Service actif"
else
    echo "✗ Service inactif"
    exit 1
fi

# Test 2: Redis
echo "2. Vérification Redis..."
if redis-cli ping > /dev/null 2>&1; then
    echo "✓ Redis accessible"
else
    echo "✗ Redis inaccessible"
    exit 1
fi

# Test 3: Port en écoute
echo "3. Vérification du port..."
if ss -tlnp | grep -q ":8083"; then
    echo "✓ Port 8080 en écoute"
else
    echo "✗ Port 8080 non en écoute"
    exit 1
fi

# Test 4: Initialize
echo "4. Test d'initialisation..."
RESPONSE=$(curl -k -s \
  -H "Authorization: Bearer $MCP_TOKEN" \
  -H "Content-Type: application/json" \
  -X POST \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0.0"}}}' \
  $MCP_URL)

if echo "$RESPONSE" | grep -q "result"; then
    echo "✓ Initialisation réussie"
else
    echo "✗ Échec d'initialisation: $RESPONSE"
    exit 1
fi

# Test 5: List tools
echo "5. Test de liste des outils..."
RESPONSE=$(curl -k -s \
  -H "Authorization: Bearer $MCP_TOKEN" \
  -H "Content-Type: application/json" \
  -X POST \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
  $MCP_URL)

if echo "$RESPONSE" | grep -q "read_exchange_table"; then
    echo "✓ Outils disponibles"
else
    echo "✗ Aucun outil trouvé: $RESPONSE"
    exit 1
fi

echo ""
echo "=== Tous les tests sont passés! ==="
```

Rendez-le exécutable et lancez-le :
```bash
chmod +x test_mcp.sh
sudo ./test_mcp.sh
```

## 11. Surveillance en temps réel

### Surveiller les logs pendant les tests

Dans un terminal :
```bash
sudo journalctl -u essensys-mcp -f
```

Dans un autre terminal, lancez vos tests. Vous verrez les requêtes et réponses en temps réel.

## Résultats attendus

- ✅ Service actif et en écoute sur le port 8080
- ✅ Réponses JSON-RPC valides avec `"jsonrpc": "2.0"`
- ✅ Liste des outils disponible (4 outils)
- ✅ Les outils peuvent lire/écrire dans Redis
- ✅ Les erreurs d'authentification sont correctement gérées
- ✅ L'accès depuis IP publique est bloqué

## Dépannage

Si les tests échouent, consultez le guide de débogage : `docs/mcp-debug.md`
