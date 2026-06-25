# Observabilité New Relic — portail utilisateur OVH

New Relic complète la stack existante sur le **VPS OVH** (`mon.essensys.fr`). Les gateways CM5 conservent **Prometheus** local.

## Composants

| Couche | Agent | Repo / rôle |
|--------|-------|-------------|
| APM Go | `newrelic-go` | `essensys-user-portal-backend` |
| Browser SPA portail | `@newrelic/browser-agent` | `essensys-user-portal-frontend` |
| Browser SPA site support | `@newrelic/browser-agent` | `essensys-support-site` |
| Infrastructure | `newrelic-infra` | rôle Ansible `newrelic_infra` |

## Prérequis (compte New Relic)

1. Créer les applications APM `essensys-user-portal-backend`, Browser `essensys-user-portal-frontend` et Browser `essensys-support-site`.
2. Générer une **Ingest License key**.
3. Restreindre le domaine Browser à `mon.essensys.fr`.
4. Stocker les secrets dans SOPS (`secrets/cloud/essensys.sops.yaml`) — voir [secrets.md](secrets.md) :

```bash
export SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"
sops secrets/cloud/essensys.sops.yaml
```

Contenu minimal (clés dans le fichier chiffré) :

```yaml
vault_newrelic_license_key: "NRII-xxxxxxxx"
vault_newrelic_browser_license_key: "NRII-xxxxxxxx"  # optionnel
```

5. Copier `group_vars/essensys/newrelic.example.yml` vers `group_vars/essensys/main.yml` et activer :

```yaml
newrelic_enabled: true
newrelic_backend_enabled: true
newrelic_browser_enabled: true
newrelic_account_id: "1234567"
newrelic_browser_application_id: "..."
newrelic_browser_agent_id: "..."
```

## Déploiement

```bash
ansible-playbook -i inventory support-site.yml --ask-vault-pass
```

Le rôle `newrelic_infra` est **no-op** si `newrelic_enabled: false`.

## Vérification post-déploiement

```bash
# Sur le VPS
sudo systemctl is-active newrelic-infra
sudo systemctl is-active essensys-portal-backend
curl -sS https://mon.essensys.fr/api/portal/health

# Logs (aucune license key en clair)
journalctl -u essensys-portal-backend -n 50 --no-pager
```

Dans New Relic UI (délai ~5 min) :

- APM : transactions `/api/portal/*`, `/api/gateway/*`
- Browser portail : page views sur `/portal/*`
- Browser site support : page views + clics liens (`support_link_click`) sur `mon.essensys.fr`
- Infrastructure : host `ovh-mon-essensys`

### Liens les plus cliqués (site support)

Dans **Query your data** (NRQL) :

```sql
SELECT count(*) FROM PageAction
WHERE appName = 'essensys-support-site' AND actionName = 'support_link_click'
FACET label, href, page
SINCE 7 days ago
```

## Rollback

```yaml
newrelic_enabled: false
newrelic_backend_enabled: false
newrelic_browser_enabled: false
```

Puis redéployer :

```bash
ansible-playbook -i inventory support-site.yml
```

Le portail reste fonctionnel sans agent actif.

## PostgreSQL OVH (intégration Infrastructure)

La base **`essensys_db`** sur le VPS est monitorée via `nri-postgresql` avec les mêmes identifiants que le backend portail.

Variables partagées (`group_vars/essensys/database.yml`) :

| Variable | Défaut OVH |
|----------|------------|
| `portal_db_host` | `127.0.0.1` |
| `portal_db_port` | `5432` |
| `portal_db_user` | `essensys` |
| `portal_db_name` | `essensys_db` |
| `portal_db_password` | SOPS (`secrets/cloud/essensys.sops.yaml`) |
| `newrelic_postgresql_instance_name` | `essensys-ovh-postgresql` |

Référence locale : `config/.env` (`PORTAL_DB_*`) et `config/database.example.yml`.

Dans New Relic UI (délai ~5 min après deploy) :

- **Infrastructure** → host `ovh-mon-essensys` → onglet **Integrations** → `nri-postgresql`
- **Databases** (vue unifiée) → instance `essensys-ovh-postgresql` / base `essensys_db`
- **Query** (NRQL) : `FROM PostgresqlDatabaseSample SELECT latest(database.connections) FACET databaseName SINCE 1 hour ago`

> Le fichier d’intégration doit utiliser le format `integrations:` (pas l’ancien `integration_name` / `instance`). Sinon l’agent logue `missing 'integrations' field` et aucune métrique n’est envoyée.

Le rôle accorde `pg_monitor` à l'utilisateur applicatif pour les métriques `all-data`.

## Intégration Nginx (optionnelle)

L’intégration `nri-nginx` est **désactivée par défaut** (`newrelic_infra_integrations.nginx: false`) car elle requiert `stub_status` sur Nginx. Pour l’activer, ajouter un endpoint `/status` local puis passer `nginx: true`.

## Références

- Prompt : `prompts/NewRelicUserPortal.md`
- OpenSpec : `essensys-raspberry-gateway/openspec/changes/essensys-newrelic-user-portal/`
