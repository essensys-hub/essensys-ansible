# Vérification de la configuration des ports Essensys

Ce document vérifie que la configuration des ports est correcte pour :
- ✅ Port 80 local : Obligatoire pour les armoires Essensys
- ✅ Port 443 WAN : Obligatoire pour l'accès HTTPS depuis Internet

## Architecture des ports

```
┌─────────────────────────────────────────────────────────────┐
│                    RÉSEAU LOCAL (LAN)                        │
│                                                               │
│  Armoires Essensys → Port 80 (Nginx) → Backend Port 7070    │
│  Navigateurs locaux → Port 80 (Nginx) → Frontend            │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                    INTERNET (WAN)                            │
│                                                               │
│  Navigateurs → Port 443 (Traefik HTTPS) → Frontend Port 9090│
│  Admin → Port 443 (Traefik HTTPS) → /api/admin/inject       │
└─────────────────────────────────────────────────────────────┘
```

## Configuration actuelle

### 1. Port 80 Local (Nginx) - ✅ CORRECT

**Fichier**: `roles/raspberry_nginx/templates/essensys.template.j2`

- ✅ Écoute sur port 80 avec `default_server`
- ✅ Autorise les réseaux locaux (127.0.0.1, 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16)
- ✅ Bloque l'accès depuis Internet (`deny all`)
- ✅ Proxy `/api/` vers backend sur port 7070
- ✅ Sert le frontend sur `/` depuis `{{ frontend_dir }}/dist`
- ✅ Pas de redirection automatique (`port_in_redirect off`)

**Vérification**:
```bash
# Vérifier que Nginx écoute sur le port 80
sudo ss -tlnp | grep :80

# Tester l'accès local
curl http://localhost/api/serverinfos
curl http://localhost/
```

### 2. Port 443 WAN (Traefik) - ✅ CORRECT

**Fichier**: `roles/raspberry_traefik/templates/traefik.yml.j2`

- ✅ Écoute sur port 443 (`websecure` entryPoint)
- ✅ Certificats SSL via Let's Encrypt (TLS-ALPN challenge)
- ✅ Pas d'entryPoint `web` (port 80) - Nginx gère le port 80

**Fichier**: `roles/raspberry_traefik/templates/wan-routes.yml.j2`

- ✅ Frontend WAN accessible en HTTPS avec authentification basique
- ✅ `/api/admin/inject` accessible en HTTPS avec authentification
- ✅ Autres API bloquées en WAN (403 Forbidden)
- ✅ Routes de redirection HTTP→HTTPS désactivées (Traefik n'écoute pas sur port 80)

**Vérification**:
```bash
# Vérifier que Traefik écoute sur le port 443
sudo ss -tlnp | grep :443

# Vérifier que Traefik n'écoute PAS sur le port 80
sudo ss -tlnp | grep :80 | grep traefik
# Ne doit rien retourner
```

### 3. Backend (Port 7070) - ✅ CORRECT

**Fichier**: `roles/raspberry_backend/tasks/main.yml`

- ✅ Backend configuré pour écouter sur port 7070
- ✅ Nginx proxy `/api/` vers `http://127.0.0.1:7070/api/`
- ✅ Configuration compatible client legacy BP_MQX_ETH (single-packet TCP)

**Vérification**:
```bash
# Vérifier que le backend écoute sur le port 7070
sudo ss -tlnp | grep :7070

# Tester directement le backend
curl http://localhost:7070/health
```

### 4. Frontend Interne (Port 9090) - ✅ CORRECT

**Fichier**: `roles/raspberry_nginx/templates/nginx-frontend-internal.conf.j2`

- ✅ Nginx écoute sur port 9090 pour servir le frontend en interne
- ✅ Traefik proxy vers `http://127.0.0.1:9090` pour le frontend WAN
- ✅ Frontend servi depuis `{{ frontend_dir }}/dist`

**Vérification**:
```bash
# Vérifier que Nginx écoute sur le port 9090
sudo ss -tlnp | grep :9090

# Tester le frontend interne
curl http://localhost:9090/
```

## Points critiques à vérifier

### ✅ Port 80 local obligatoire pour armoires Essensys

Les armoires Essensys (BP_MQX_ETH) ont le port 80 hardcodé dans leur firmware. Elles doivent pouvoir accéder aux API sur le port 80.

**Configuration actuelle**:
- ✅ Nginx écoute sur port 80
- ✅ Nginx proxy `/api/*` vers backend port 7070
- ✅ Pas de redirection HTTP→HTTPS sur le port 80 local
- ✅ Accès autorisé depuis réseaux locaux (192.168.0.0/16, etc.)

### ✅ Port 443 WAN obligatoire pour accès HTTPS

L'accès depuis Internet doit se faire uniquement en HTTPS avec authentification.

**Configuration actuelle**:
- ✅ Traefik écoute sur port 443
- ✅ Frontend WAN accessible en HTTPS avec auth basique
- ✅ `/api/admin/inject` accessible en HTTPS avec auth
- ✅ Autres API bloquées en WAN
- ✅ Traefik n'écoute pas sur port 80 (pas de conflit avec Nginx)

## Checklist de vérification

Avant de déployer, vérifier :

- [ ] Nginx écoute sur le port 80 (`sudo ss -tlnp | grep :80`)
- [ ] Traefik écoute sur le port 443 (`sudo ss -tlnp | grep :443`)
- [ ] Traefik n'écoute PAS sur le port 80
- [ ] Backend écoute sur le port 7070 (`sudo ss -tlnp | grep :7070`)
- [ ] Frontend interne écoute sur le port 9090 (`sudo ss -tlnp | grep :9090`)
- [ ] Les armoires Essensys peuvent accéder aux API sur port 80
- [ ] L'accès WAN fonctionne en HTTPS avec authentification
- [ ] Pas de redirection HTTP→HTTPS sur le port 80 local

## Commandes de diagnostic

```bash
# Voir tous les ports en écoute
sudo ss -tlnp

# Vérifier les services actifs
sudo systemctl status nginx
sudo systemctl status traefik
sudo systemctl status essensys-backend

# Tester l'accès local (port 80)
curl -v http://localhost/api/serverinfos
curl -v http://localhost/

# Tester l'accès WAN (port 443) - nécessite authentification
curl -v -u username:password https://votre-domaine.com/
curl -v -u username:password https://votre-domaine.com/api/admin/inject

# Vérifier les logs
sudo tail -f /var/log/nginx/essensys-access.log
sudo tail -f /var/log/traefik/traefik.log
```

## Résumé

✅ **Configuration correcte** :
- Port 80 local : Nginx gère le frontend et les API pour les armoires Essensys
- Port 443 WAN : Traefik gère l'accès HTTPS sécurisé depuis Internet
- Pas de conflit entre les deux
- Les armoires Essensys peuvent accéder aux API sur le port 80
- L'accès WAN est sécurisé en HTTPS avec authentification
