# Commandes curl pour tester UniFi Protect

## 1. Test direct de l'API UniFi Protect (depuis le Raspberry Pi)

### Test de l'endpoint bootstrap (liste des caméras)
```bash
# Remplacez YOUR_API_KEY par votre clé API
# IMPORTANT: L'endpoint correct est /unifi-api/protect/api/bootstrap
curl -k -X GET "https://192.168.0.1/unifi-api/protect/api/bootstrap" \
  -H "X-API-KEY: YOUR_API_KEY" \
  -H "Accept: application/json" \
  -v
```

### Test avec votre clé API actuelle
```bash
curl -k -X GET "https://192.168.0.1/unifi-api/protect/api/bootstrap" \
  -H "X-API-KEY: ${UNIFI_API_KEY}" \
  -H "Accept: application/json" \
  -v
```

### Test d'un snapshot de caméra (remplacez CAMERA_ID)
```bash
curl -k -X GET "https://192.168.0.1/unifi-api/protect/api/cameras/CAMERA_ID/snapshot" \
  -H "X-API-KEY: ${UNIFI_API_KEY}" \
  -H "Accept: application/json" \
  -o /tmp/snapshot.jpg \
  -v
```

## 2. Test via le backend proxy (depuis le Raspberry Pi)

### Test de l'endpoint /api/unifi/cameras
```bash
# Test depuis localhost
curl -X GET "http://localhost:7070/api/unifi/cameras" \
  -H "Content-Type: application/json" \
  -v

# Test depuis l'extérieur (si accessible)
curl -X GET "http://mon.essensys.fr/api/unifi/cameras" \
  -H "Content-Type: application/json" \
  -v
```

### Test d'un snapshot via le backend
```bash
# Remplacez CAMERA_ID par l'ID d'une caméra réelle
curl -X GET "http://localhost:7070/api/unifi/cameras/CAMERA_ID/snapshot" \
  -o /tmp/snapshot.jpg \
  -v
```

## 3. Tests de diagnostic

### Vérifier si le backend répond
```bash
curl -X GET "http://localhost:7070/health" -v
```

### Vérifier si UniFi est configuré (devrait retourner 503 si non configuré)
```bash
curl -X GET "http://localhost:7070/api/unifi/cameras" \
  -H "Content-Type: application/json" \
  -w "\nHTTP Status: %{http_code}\n" \
  -v
```

### Test avec affichage des headers seulement
```bash
curl -I -X GET "http://localhost:7070/api/unifi/cameras" -v
```

### Test avec timeout
```bash
curl --max-time 10 -X GET "http://localhost:7070/api/unifi/cameras" -v
```

## 4. Script de test complet

Créez un fichier `test-unifi.sh` :

```bash
#!/bin/bash

API_KEY="${UNIFI_API_KEY:?Définir UNIFI_API_KEY}"
UNIFI_BASE="https://192.168.0.1"
BACKEND_URL="http://localhost:7070"

echo "=== Test 1: API UniFi Protect directe (bootstrap) ==="
curl -k -X GET "${UNIFI_BASE}/unifi-api/protect/api/bootstrap" \
  -H "X-API-KEY: ${API_KEY}" \
  -H "Accept: application/json" \
  -w "\nHTTP Status: %{http_code}\n" \
  -s | head -20

echo -e "\n=== Test 2: Backend proxy (/api/unifi/cameras) ==="
curl -X GET "${BACKEND_URL}/api/unifi/cameras" \
  -H "Content-Type: application/json" \
  -w "\nHTTP Status: %{http_code}\n" \
  -s | head -20

echo -e "\n=== Test 3: Health check backend ==="
curl -X GET "${BACKEND_URL}/health" -s

echo -e "\n"
```

Rendez-le exécutable et lancez-le :
```bash
chmod +x test-unifi.sh
./test-unifi.sh
```

## 5. Interprétation des résultats

### Code 200 OK
- ✅ L'API fonctionne correctement
- Vous devriez voir un JSON avec la liste des caméras

### Code 401 Unauthorized
- ❌ La clé API est invalide ou expirée
- Vérifiez votre clé API dans l'interface UniFi Protect

### Code 503 Service Unavailable
- ❌ UniFi Protect n'est pas configuré dans le backend
- Vérifiez `/opt/essensys/backend/config.yaml`

### Code 500 Internal Server Error
- ❌ Erreur de connexion à UniFi Protect
- Vérifiez les logs : `sudo journalctl -u essensys-backend -n 50`

### Code 000 ou timeout
- ❌ Le backend n'est pas démarré ou inaccessible
- Vérifiez : `sudo systemctl status essensys-backend`

## 6. Extraction de l'ID d'une caméra

Si le bootstrap fonctionne, extrayez les IDs des caméras :
```bash
curl -k -X GET "https://192.168.0.1/unifi-api/protect/api/bootstrap" \
  -H "X-API-KEY: ${UNIFI_API_KEY}" \
  -H "Accept: application/json" \
  -s | jq '.cameras[] | {id: .id, name: .name}'
```

Ou sans jq :
```bash
curl -k -X GET "https://192.168.0.1/unifi-api/protect/api/bootstrap" \
  -H "X-API-KEY: ${UNIFI_API_KEY}" \
  -H "Accept: application/json" \
  -s | grep -o '"id":"[^"]*"' | head -5
```

## 7. Test d'un snapshot spécifique

Une fois que vous avez un ID de caméra (ex: `60f1234567890abcdef12345`) :

```bash
CAMERA_ID="60f1234567890abcdef12345"

# Via API directe
curl -k -X GET "https://192.168.0.1/unifi-api/protect/api/cameras/${CAMERA_ID}/snapshot" \
  -H "X-API-KEY: ${UNIFI_API_KEY}" \
  -H "Accept: application/json" \
  -o /tmp/snapshot-direct.jpg

# Via backend proxy
curl -X GET "http://localhost:7070/api/unifi/cameras/${CAMERA_ID}/snapshot" \
  -o /tmp/snapshot-proxy.jpg

# Vérifier les images
ls -lh /tmp/snapshot-*.jpg
file /tmp/snapshot-*.jpg
```
