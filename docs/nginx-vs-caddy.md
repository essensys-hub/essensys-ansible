# Nginx vs Caddy - Configuration actuelle

## Configuration en production

**Nginx est utilisé**, Caddy est **désactivé**.

### Configuration actuelle (`install.raspberrypi.yml`)

```yaml
roles:
  # Nginx pour port 80 (client legacy - tolérant aux requêtes HTTP non-standard)
  - raspberry_nginx
  # Traefik pour port 443 avec authentification
  - raspberry_traefik
  # Caddy désactivé (rejette les requêtes HTTP non-standard du client legacy)
  # - raspberry_caddy
```

## Pourquoi Nginx et pas Caddy ?

### Problème avec Caddy

Caddy **rejette les requêtes HTTP non-standard** envoyées par le client legacy BP_MQX_ETH (armoires Essensys). Ces requêtes ont des caractéristiques non-standard :
- Headers HTTP non conformes
- Format de requête spécifique
- Nécessité de réponses en un seul paquet TCP

### Avantage de Nginx

Nginx est **plus tolérant** avec les requêtes HTTP non-standard et peut être configuré pour :
- Accepter les requêtes du client legacy BP_MQX_ETH
- Bufferiser les réponses complètes avant envoi (single-packet TCP)
- Gérer les headers non-standard
- Proxy vers le backend sur le port 7070

## Architecture actuelle

```
┌─────────────────────────────────────────────────────────┐
│                    RÉSEAU LOCAL                         │
│                                                          │
│  Armoires Essensys → Port 80 (Nginx) → Backend 7070    │
│  Navigateurs locaux → Port 80 (Nginx) → Frontend        │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│                    INTERNET (WAN)                        │
│                                                          │
│  Navigateurs → Port 443 (Traefik HTTPS) → Frontend     │
└─────────────────────────────────────────────────────────┘
```

### Services utilisés

| Service | Port | Usage | Raison |
|---------|------|-------|--------|
| **Nginx** | 80 | Local (LAN) | Tolérant aux requêtes HTTP non-standard du client legacy |
| **Traefik** | 443 | WAN (HTTPS) | Gestion HTTPS avec Let's Encrypt et authentification |
| **Caddy** | - | Désactivé | Rejette les requêtes non-standard du client legacy |

## Configuration Nginx pour client legacy

La configuration Nginx (`essensys.template.j2`) inclut des optimisations spécifiques pour le client legacy :

```nginx
location /api/ {
    # Bufferiser la réponse complète pour single-packet TCP
    proxy_buffering on;
    proxy_buffer_size 4k;
    proxy_buffers 8 4k;
    proxy_busy_buffers_size 8k;
    proxy_max_temp_file_size 0;
    
    # Désactiver gzip pour éviter la fragmentation
    gzip off;
    
    # Headers pour compatibilité client legacy
    proxy_set_header Connection "close";
}
```

## Si vous voulez utiliser Caddy

Si vous souhaitez utiliser Caddy à la place de Nginx, vous devez :

1. **Activer le rôle Caddy** dans `install.raspberrypi.yml` :
```yaml
roles:
  # - raspberry_nginx  # Désactiver Nginx
  - raspberry_caddy    # Activer Caddy
```

2. **Vérifier la compatibilité** avec le client legacy BP_MQX_ETH :
   - Les requêtes HTTP non-standard doivent être acceptées
   - Les réponses doivent être bufferisées (single-packet TCP)
   - Les headers non-standard doivent être préservés

3. **Tester** avec une armoire Essensys réelle pour confirmer que tout fonctionne

⚠️ **Attention** : D'après les commentaires dans le code, Caddy rejette les requêtes HTTP non-standard du client legacy, donc il n'est probablement pas compatible sans modifications.

## Résumé

- ✅ **Nginx** : Utilisé en production pour le port 80 (compatible client legacy)
- ✅ **Traefik** : Utilisé en production pour le port 443 (HTTPS WAN)
- ❌ **Caddy** : Désactivé (non compatible avec client legacy)

La configuration actuelle est optimale pour la compatibilité avec les armoires Essensys (BP_MQX_ETH).
