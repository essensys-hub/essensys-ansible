# Correction du problème de redirection HTTP vers HTTPS

## Problème

Lors de l'accès au port 80, vous êtes automatiquement redirigé vers HTTPS avec l'IP `192.168.1.101`.

## Cause

Traefik avait des routes configurées pour rediriger HTTP vers HTTPS sur l'entryPoint `web` (port 80), même si cet entryPoint était commenté dans la configuration principale.

## Solution appliquée

Les routes de redirection HTTP->HTTPS ont été désactivées dans Traefik car :
- Le port 80 est géré uniquement par Nginx pour l'accès local
- Traefik ne doit écouter que sur le port 443 (HTTPS) pour l'accès WAN

## Actions à effectuer sur le Raspberry Pi

1. **Redémarrer Traefik** pour appliquer la nouvelle configuration :
```bash
sudo systemctl restart traefik
```

2. **Vérifier que Traefik n'écoute pas sur le port 80** :
```bash
sudo ss -tlnp | grep :80
```

Vous devriez voir uniquement Nginx sur le port 80, pas Traefik.

3. **Vérifier que Nginx fonctionne correctement** :
```bash
curl http://localhost/
```

Vous devriez obtenir le frontend sans redirection.

4. **Vérifier les logs Traefik** pour confirmer :
```bash
sudo tail -f /var/log/traefik/traefik.log
```

## Si le problème persiste

Si vous êtes toujours redirigé après le redémarrage de Traefik :

1. **Vérifier que Traefik n'a pas d'entryPoint web actif** :
```bash
sudo cat /etc/traefik/traefik.yml | grep -A 5 "entryPoints:"
```

L'entryPoint `web` doit être commenté.

2. **Vérifier la configuration dynamique** :
```bash
sudo cat /etc/traefik/dynamic/wan-routes.yml | grep -A 10 "frontend-wan-redirect"
```

Les routes de redirection doivent être commentées.

3. **Vérifier si un autre service écoute sur le port 80** :
```bash
sudo lsof -i :80
```

4. **Vérifier la configuration Nginx** pour des redirections :
```bash
sudo grep -r "return.*301\|return.*302\|redirect" /etc/nginx/sites-enabled/
```

## Configuration attendue

- **Port 80** : Nginx uniquement (frontend local + API locales)
- **Port 443** : Traefik uniquement (frontend WAN HTTPS avec authentification)
- **Pas de redirection automatique** HTTP->HTTPS sur le port 80 local
