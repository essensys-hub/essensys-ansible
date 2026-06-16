# Vérification UniFi Protect - Guide rapide

## 1. Vérifier que le backend répond

```bash
curl http://localhost:7070/api/unifi/cameras
```

**Résultat attendu** : JSON avec la liste des caméras

**Si erreur 503** : Vérifier la configuration dans `/opt/essensys/backend/config.yaml`

**Si erreur 500** : Vérifier les logs backend

## 2. Vérifier les logs backend

```bash
sudo journalctl -u essensys-backend -n 50 | grep -i unifi
```

Chercher :
- `"Initialized UniFi Protect Handler"` → ✅ UniFi initialisé
- `"authentication required"` → ❌ Problème d'authentification
- `"all endpoints failed"` → ❌ Problème de connexion à UniFi

## 3. Tester l'API UniFi directement

```bash
API_KEY="${UNIFI_API_KEY:?Définir UNIFI_API_KEY}"
curl -k -X GET "https://192.168.0.1/proxy/protect/integration/v1/cameras" \
  -H "X-API-KEY: ${API_KEY}" \
  -H "Accept: application/json" \
  -s | jq 'length'  # Devrait afficher le nombre de caméras
```

## 4. Vérifier la configuration

```bash
sudo cat /opt/essensys/backend/config.yaml | grep -A 5 unifi
```

Doit contenir :
```yaml
unifi:
  enabled: true
  base_url: "https://192.168.0.1"
  api_key: "${UNIFI_API_KEY}"
```

## 5. Tester un snapshot

Une fois que vous avez l'ID d'une caméra (ex: `605e92d10354ce03870003ed`) :

```bash
CAMERA_ID="605e92d10354ce03870003ed"
curl http://localhost:7070/api/unifi/cameras/${CAMERA_ID}/snapshot \
  -o /tmp/snapshot.jpg

# Vérifier l'image
file /tmp/snapshot.jpg
# Devrait afficher: JPEG image data
```

## 6. Vérifier le frontend

1. Ouvrir `https://mon.essensys.fr/unifi-protect` dans le navigateur
2. Vérifier la console du navigateur (F12) pour les erreurs
3. Les caméras devraient apparaître dans la grille

## Problèmes courants

### Backend retourne 503
- Vérifier que `enabled: true` dans config.yaml
- Vérifier que `api_key` est configuré

### Backend retourne 500
- Vérifier les logs : `sudo journalctl -u essensys-backend -n 100`
- Vérifier que l'API key fonctionne avec curl direct

### Frontend affiche "Failed to fetch"
- Vérifier que le backend répond : `curl http://localhost:7070/api/unifi/cameras`
- Vérifier les CORS dans les logs backend
- Vérifier la console du navigateur pour les erreurs détaillées
