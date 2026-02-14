# Configuration OpenClaw pour se connecter au serveur MCP Essensys

Ce guide vous explique comment configurer OpenClaw sur votre workstation pour se connecter au serveur MCP SSE sur le Raspberry Pi.

## Prérequis

- OpenClaw installé sur votre workstation
- Accès réseau au Raspberry Pi (même réseau local ou VPN)
- Token MCP du Raspberry Pi

## 1. Récupérer le token MCP depuis le Raspberry Pi

Sur le Raspberry Pi, récupérez le token :

```bash
# Via SSH sur le Raspberry Pi
ssh essensys@essensys-server
sudo cat /etc/essensys/mcp.token
```

Copiez le token, vous en aurez besoin pour la configuration.

## 2. Vérifier l'accessibilité du serveur MCP

Depuis votre workstation, testez la connexion au serveur MCP :

```bash
# Remplacez ESSENSYS_SERVER_IP par l'IP du Raspberry Pi
# Remplacez MCP_TOKEN par le token récupéré

curl -k \
  -H "Authorization: Bearer MCP_TOKEN" \
  -H "Accept: text/event-stream" \
  --max-time 2 \
  http://ESSENSYS_SERVER_IP:8083/sse
```

Si vous obtenez un code 200 ou un timeout (normal pour SSE), la connexion fonctionne.

## 3. Configuration OpenClaw

### Option A : Configuration via fichier JSON (si supporté)

Créez un fichier de configuration `essensys-mcp.json` :

```json
{
  "mcpServers": {
    "essensys": {
      "url": "http://ESSENSYS_SERVER_IP:8083",
      "transport": "sse",
      "headers": {
        "Authorization": "Bearer MCP_TOKEN"
      },
      "endpoints": {
        "sse": "/sse",
        "messages": "/messages"
      }
    }
  }
}
```

### Option B : Configuration via interface OpenClaw

1. Ouvrez OpenClaw
2. Allez dans les paramètres/Settings
3. Ajoutez un nouveau serveur MCP :
   - **Nom** : Essensys MCP
   - **Type de transport** : SSE (Server-Sent Events)
   - **URL de base** : `http://ESSENSYS_SERVER_IP:8083`
   - **Endpoint SSE** : `/sse`
   - **Endpoint Messages** : `/messages`
   - **Authentification** : Bearer Token
   - **Token** : (collez le token MCP)

### Option C : Configuration via variables d'environnement

Si OpenClaw supporte les variables d'environnement :

```bash
export MCP_SERVER_URL="http://ESSENSYS_SERVER_IP:8083"
export MCP_SERVER_TOKEN="MCP_TOKEN"
export MCP_SERVER_TYPE="sse"
```

## 4. Vérifier la connexion

Une fois configuré, OpenClaw devrait :

1. Établir une connexion SSE vers `/sse`
2. Recevoir les événements du serveur MCP
3. Pouvoir envoyer des messages JSON-RPC vers `/messages`

## 5. Tester les outils MCP

Une fois connecté, vous devriez pouvoir :

- **Lister les outils** : `read_exchange_table`, `read_exchange_value`, `set_exchange_value`, `send_order`
- **Appeler `send_order`** pour allumer la lumière "chevet chambre petit 3" :
  ```json
  {
    "name": "send_order",
    "arguments": {
      "params_json": "[{\"k\":621,\"v\":\"64\"}]"
    }
  }
  ```

## 6. Résolution de problèmes

### Erreur : "Connection refused"
- Vérifiez que le serveur MCP est démarré sur le Raspberry Pi
- Vérifiez que le port 8083 est accessible depuis votre workstation
- Vérifiez le firewall du Raspberry Pi

### Erreur : "Unauthorized" ou "Invalid token"
- Vérifiez que le token est correct
- Vérifiez le format : `Authorization: Bearer TOKEN` (avec un espace après "Bearer")

### Erreur : "Forbidden: Access restricted to private subnets"
- Le serveur MCP vérifie que la connexion vient d'une IP privée
- Assurez-vous que votre workstation est sur le même réseau local que le Raspberry Pi
- Si vous êtes sur un VPN, vérifiez que l'IP VPN est dans une plage privée

### Le serveur ne répond pas
- Vérifiez les logs du serveur MCP sur le Raspberry Pi :
  ```bash
  ssh essensys@essensys-server
  sudo journalctl -u essensys-mcp -f
  ```

## 7. Informations de connexion

**Serveur MCP Essensys :**
- **URL** : `http://ESSENSYS_SERVER_IP:8083`
- **Transport** : SSE (Server-Sent Events)
- **Endpoint SSE** : `/sse` (GET)
- **Endpoint Messages** : `/messages` (POST)
- **Authentification** : Bearer Token
- **Token** : Dans `/etc/essensys/mcp.token` sur le Raspberry Pi

**Outils disponibles :**
- `read_exchange_table` : Lire la table d'échange complète
- `read_exchange_value` : Lire une valeur spécifique
- `set_exchange_value` : Définir une valeur
- `send_order` : Envoyer une commande (action) au backend

## 8. Exemple de commande pour allumer la lumière

Via OpenClaw, appelez l'outil `send_order` avec :

```json
{
  "params_json": "[{\"k\":621,\"v\":\"64\"}]"
}
```

Cela allumera la lumière "chevet chambre petit 3".
