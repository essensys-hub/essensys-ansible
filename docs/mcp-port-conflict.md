# Résolution du conflit de port 8083 pour MCP

## Problème
Le service MCP ne peut pas démarrer car le port 8083 est déjà utilisé par un autre processus.

## Diagnostic

### 1. Identifier le processus utilisant le port 8083

```bash
# Méthode 1: Avec ss
sudo ss -tlnp | grep :8083

# Méthode 2: Avec lsof
sudo lsof -i :8083

# Méthode 3: Avec netstat
sudo netstat -tlnp | grep :8083
```

### 2. Vérifier si c'est une instance MCP qui tourne déjà

```bash
# Vérifier les processus MCP
ps aux | grep essensys-mcp

# Vérifier si le service est en cours d'exécution
sudo systemctl status essensys-mcp
```

## Solutions

### Solution 1: Arrêter le processus qui utilise le port

Si c'est une ancienne instance de MCP :

```bash
# Arrêter le service
sudo systemctl stop essensys-mcp

# Vérifier qu'il n'y a plus de processus
ps aux | grep essensys-mcp

# Tuer manuellement si nécessaire
sudo pkill -f essensys-mcp

# Vérifier que le port est libre
sudo ss -tlnp | grep :8083
```

### Solution 2: Changer le port du service MCP

Si vous avez besoin d'utiliser un autre port (par exemple 8081) :

1. Modifier le fichier de service :
```bash
sudo nano /etc/systemd/system/essensys-mcp.service
```

2. Changer le port dans la ligne ExecStart :
```
ExecStart=/usr/local/bin/essensys-mcp -mode sse -port 8081 -token ...
```

3. Recharger et redémarrer :
```bash
sudo systemctl daemon-reload
sudo systemctl restart essensys-mcp
```

### Solution 3: Identifier et arrêter l'autre service

Si un autre service utilise le port 8083 :

```bash
# Identifier le processus
sudo lsof -i :8083

# Arrêter le service correspondant (remplacer SERVICE_NAME par le nom réel)
sudo systemctl stop SERVICE_NAME

# Ou tuer le processus directement (remplacer PID par le PID réel)
sudo kill PID
```

## Vérification

Après avoir libéré le port :

```bash
# Vérifier que le port est libre
sudo ss -tlnp | grep :8083

# Redémarrer le service MCP
sudo systemctl restart essensys-mcp

# Vérifier le statut
sudo systemctl status essensys-mcp

# Vérifier les logs
sudo journalctl -u essensys-mcp -n 20
```

## Prévention

Pour éviter ce problème à l'avenir :

1. Vérifier que le service MCP est bien arrêté avant de le redémarrer
2. Utiliser `systemctl restart` plutôt que de lancer manuellement le binaire
3. Vérifier les ports avant l'installation avec `ss -tlnp | grep :8083`
