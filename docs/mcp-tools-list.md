# Liste des outils MCP disponibles

Le serveur MCP Essensys expose **4 outils** pour interagir avec le système d'automatisation.

## 1. `read_exchange_table`

**Description** : Lit toutes les valeurs de la table d'échange.

**Paramètres** :
- `client_id` (string, optionnel) : ID du client à lire (défaut: `"default"`)

**Retour** : JSON avec toutes les valeurs de la table d'échange (map index → valeur)

**Exemple d'utilisation** :
```json
{
  "name": "read_exchange_table",
  "arguments": {
    "client_id": "default"
  }
}
```

**Exemple de réponse** :
```json
{
  "1": "0",
  "2": "1",
  "621": "64",
  ...
}
```

---

## 2. `read_exchange_value`

**Description** : Lit une valeur spécifique de la table d'échange par index.

**Paramètres** :
- `index` (number, requis) : Index à lire
- `client_id` (string, optionnel) : ID du client (défaut: `"default"`)

**Retour** : La valeur de l'index (string), ou chaîne vide si l'index n'existe pas

**Exemple d'utilisation** :
```json
{
  "name": "read_exchange_value",
  "arguments": {
    "index": 621,
    "client_id": "default"
  }
}
```

**Exemple de réponse** :
```
64
```

---

## 3. `set_exchange_value`

**Description** : Définit directement une valeur dans la table d'échange.

**⚠️ Attention** : Cet outil contourne la logique de queue d'ordres. Utilisez `send_order` pour les commandes normales.

**Paramètres** :
- `index` (number, requis) : Index à définir
- `value` (string, requis) : Valeur à définir
- `client_id` (string, optionnel) : ID du client (défaut: `"default"`)

**Retour** : Message de confirmation

**Exemple d'utilisation** :
```json
{
  "name": "set_exchange_value",
  "arguments": {
    "index": 621,
    "value": "64",
    "client_id": "default"
  }
}
```

**Exemple de réponse** :
```
Set index 621 to '64' for client default
```

---

## 4. `send_order`

**Description** : Envoie une commande (action) au backend via la queue globale d'actions. C'est l'outil recommandé pour envoyer des commandes au système.

**Paramètres** :
- `params_json` (string, requis) : JSON string représentant les paramètres (liste ExchangeKV)
  - Format : `[{"k": index, "v": "valeur"}]`
  - Exemple : `[{"k":621,"v":"64"}]`
- `guid` (string, optionnel) : ID unique pour l'action (auto-généré si vide)

**Retour** : Message de confirmation avec le GUID généré

**Exemple d'utilisation** :
```json
{
  "name": "send_order",
  "arguments": {
    "params_json": "[{\"k\":621,\"v\":\"64\"}]"
  }
}
```

**Exemple avec GUID personnalisé** :
```json
{
  "name": "send_order",
  "arguments": {
    "guid": "my-custom-guid-123",
    "params_json": "[{\"k\":621,\"v\":\"64\"}]"
  }
}
```

**Exemple de réponse** :
```
Order sent with GUID mcp-1234567890123456789
```

**Comment ça fonctionne** :
1. L'outil ajoute la commande à la queue Redis `essensys:global:actions`
2. Le backend Essensys lit automatiquement cette queue
3. Le backend traite la commande et l'envoie aux robots

---

## Résumé des outils

| Outil | Description | Usage principal |
|-------|------------|-----------------|
| `read_exchange_table` | Lire toute la table | Consultation complète |
| `read_exchange_value` | Lire une valeur | Consultation d'un index |
| `set_exchange_value` | Définir une valeur | Modification directe (rare) |
| `send_order` | Envoyer une commande | **Action recommandée** |

## Recommandation

Pour envoyer des commandes au système (allumer/éteindre des lumières, etc.), utilisez **`send_order`**. C'est l'outil qui respecte le flux normal de traitement des commandes via la queue d'actions.

## Exemple complet : Allumer la lumière "chevet chambre petit 3"

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "send_order",
    "arguments": {
      "params_json": "[{\"k\":621,\"v\":\"64\"}]"
    }
  }
}
```

Où :
- `621` = Index pour "Scenario_Allumer_CHB_LSB" (Allumer lumières Chambres LSB)
- `64` = Bit 6 activé (Lampe de la petite chambre 3)
