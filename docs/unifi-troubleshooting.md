# Diagnostic UniFi Protect - V.1.2.2

## Vérifications à faire

### 1. Vérifier que le backend est sur V.1.2.2

```bash
cd /opt/essensys/backend
git branch
# Doit afficher: * V.1.2.2
```

Si ce n'est pas le cas :
```bash
cd /opt/essensys/backend
git fetch --all --tags
git checkout V.1.2.2
```

### 2. Vérifier que le backend a été recompilé avec UniFi

```bash
# Vérifier que le binaire existe et est récent
ls -lh /opt/essensys/backend/server

# Vérifier que le package unifi existe
ls -la /opt/essensys/backend/internal/unifi/
# Doit afficher: client.go, models.go
```

Si le package n'existe pas, recompiler :
```bash
cd /opt/essensys/backend
/usr/local/go/bin/go mod tidy
/usr/local/go/bin/go build -o server ./cmd/server
sudo systemctl restart essensys-backend
```

### 3. Vérifier la configuration UniFi dans config.yaml

```bash
sudo cat /opt/essensys/backend/config.yaml | grep -A 4 unifi
```

Doit afficher quelque chose comme :
```yaml
unifi:
  enabled: true
  base_url: "https://192.168.0.1"
  api_key: "votre_cle_api"
```

### 4. Vérifier les logs du backend

```bash
sudo journalctl -u essensys-backend -n 50 --no-pager
```

Chercher :
- `"Initialized UniFi Protect Handler"` → UniFi est bien initialisé
- `"WARNING: UniFi Protect enabled but API key not configured"` → API key manquante
- `"Failed to get cameras"` → Erreur de connexion à UniFi

### 5. Tester l'endpoint API directement

```bash
curl -v http://localhost:7070/api/unifi/cameras
```

Résultats possibles :
- `503 Service Unavailable` avec "UniFi Protect is not configured" → UniFi pas configuré ou API key manquante
- `500 Internal Server Error` → Erreur de connexion à UniFi Protect
- `200 OK` avec JSON → Ça fonctionne !

### 6. Vérifier que le frontend est sur V.1.2.2

```bash
cd /opt/essensys/frontend
git branch
# Doit afficher: * V.1.2.2
```

Si ce n'est pas le cas :
```bash
cd /opt/essensys/frontend
git fetch --all --tags
git checkout V.1.2.2
```

### 7. Reconstruire le frontend

```bash
cd /opt/essensys/frontend
npm install
npm run build
sudo systemctl restart essensys-frontend
# ou si c'est servi par nginx, juste recharger nginx
sudo systemctl reload nginx
```

### 8. Vérifier dans le navigateur

1. Ouvrir la console du navigateur (F12)
2. Aller sur `/dashboard`
3. Vérifier les erreurs dans la console :
   - `[UNIFI] Fetching cameras from: ...` → Le frontend essaie bien de charger les caméras
   - Erreurs 503/500 → Voir les logs backend ci-dessus

### 9. Vérifier le menu de navigation

Le menu de gauche doit contenir "UniFi Protect" avec une icône caméra.

Si ce n'est pas le cas, le frontend n'a pas été reconstruit.

## Solution rapide : Réinstaller avec Ansible

Si tout le reste échoue, réinstaller avec Ansible :

```bash
cd /opt/essensys-ansible
ansible-playbook -i inventory install.raspberrypi.yml \
  -e "unifi_enabled=true" \
  -e "unifi_base_url=https://192.168.0.1" \
  -e "unifi_api_key=votre_cle_api"
```

## Problèmes courants

### La carte UniFi n'apparaît pas sur le dashboard

**Cause** : Frontend pas reconstruit avec V.1.2.2
**Solution** : Reconstruire le frontend (étape 7)

### Erreur 503 "UniFi Protect is not configured"

**Cause** : API key manquante ou `enabled: false` dans config.yaml
**Solution** : Vérifier config.yaml (étape 3)

### Erreur 500 "Failed to retrieve cameras"

**Cause** : Problème de connexion à UniFi Protect (API key invalide, réseau, etc.)
**Solution** : 
- Vérifier l'API key
- Vérifier que `https://192.168.0.1/unifi-api/protect/bootstrap` est accessible depuis le Raspberry Pi
- Vérifier les logs backend (étape 4)

### Le menu UniFi Protect n'apparaît pas

**Cause** : Frontend pas reconstruit avec V.1.2.2
**Solution** : Reconstruire le frontend (étape 7)
