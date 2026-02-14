# Référence des ports utilisés dans Essensys

Ce document liste tous les ports utilisés par les services Essensys pour éviter les conflits.

## Ports utilisés

| Port | Service | Description | Conflit |
|------|---------|-------------|---------|
| **53** | AdGuard Home | DNS | - |
| **80** | Nginx | Frontend local + API locales (HTTP) | - |
| **443** | Traefik | Frontend WAN (HTTPS) | - |
| **1883** | Mosquitto | MQTT broker | - |
| **3000** | AdGuard Home | Interface web AdGuard | - |
| **6379** | Redis | Base de données Redis | - |
| **7070** | Backend Essensys | API backend Go | ✅ Utilisé |
| **8080** | Traefik Dashboard | Dashboard Traefik (accès local) | ⚠️ **CONFLIT avec MCP** |
| **8081** | Traefik API | API interne Traefik | - |
| **8082** | Block Service | Service de blocage Traefik | - |
| **8083** | MCP Server | Serveur MCP Essensys | ✅ **À utiliser** |
| **9091** | Monitor MQTT Debug | Interface de debug MQTT | - |

## Conflit détecté

**Port 8080** : Utilisé par :
- ✅ Traefik Dashboard (dans `traefik.yml.j2`)
- ❌ MCP Server (dans `essensys-mcp.service.j2`) - **CONFLIT**

## Solution

Le serveur MCP doit utiliser le **port 8083** au lieu de 8080 pour éviter le conflit avec Traefik Dashboard.

## Vérification des ports

Pour vérifier quels ports sont utilisés sur le système :

```bash
# Voir tous les ports en écoute
sudo ss -tlnp

# Vérifier un port spécifique
sudo ss -tlnp | grep :PORT_NUMBER

# Voir les processus utilisant un port
sudo lsof -i :PORT_NUMBER
```

## Ports recommandés pour nouveaux services

Ports libres recommandés :
- **8084-8099** : Disponibles pour nouveaux services
- **9090-9099** : Disponibles pour interfaces de debug/monitoring
- **3001-3010** : Disponibles pour services web additionnels
