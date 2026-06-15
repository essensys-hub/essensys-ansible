# Migration — backend cloud unifié (Phase 6)

Passage du mode **dual backend** (`essensys-backend` :8080 + `essensys-portal-backend` :8081) au hub unique **`essensys-cloud-backend` :8080** (`essensys-user-portal-backend` avec `CONSOLIDATED_MODE=true`).

## Variables Ansible

| Variable | Défaut | Description |
|----------|--------|-------------|
| `cloud_backend_consolidated` | `false` | Active le rôle `cloud_backend` |
| `cloud_backend_legacy_mode` | `false` | Rollback : force le dual backend même si consolidated=true |
| `cloud_backend_port` | `8080` | Port HTTP du hub unifié |
| `cloud_backend_import_machines` | `true` | Importe `machines.json` → PostgreSQL au deploy |

Formule effective : `use_cloud_backend = consolidated AND NOT legacy_mode`.

## Cutover production

1. Vérifier staging (`CONSOLIDATED_MODE=true` sur :8081) — auth, admin, legacy IoT, portail inject/exchange.
2. Mettre à jour `group_vars/essensys/main.yml` :
   ```yaml
   cloud_backend_consolidated: true
   cloud_backend_legacy_mode: false
   ```
3. Remplir les secrets vault (OAuth, SMTP, ADMIN_TOKEN) — voir `roles/cloud_backend/templates/cloud-backend.env.j2`.
4. Déployer :
   ```bash
   ansible-playbook -i inventory support-site.yml
   ```
5. Smoke tests :
   ```bash
   curl -sS https://mon.essensys.fr/api/portal/health
   curl -sS https://mon.essensys.fr/api/serverinfos
   curl -sS -H "Authorization: Bearer $ADMIN_TOKEN" https://mon.essensys.fr/api/admin/stats
   ```
6. Appliquer le snippet nginx consolidé (si `enable-https-prod.yml` a tourné en legacy) :
   ```bash
   ansible-playbook -i inventory cloud-nginx-only.yml
   ```
7. New Relic APM : app `essensys-cloud-backend`, surveiller 24h.

## Rollback (dual backend)

```yaml
cloud_backend_consolidated: true   # ou false
cloud_backend_legacy_mode: true
```

Redéployer le playbook : Ansible réactive `essensys-backend` + `essensys-portal-backend`, snippet nginx legacy (`/api/portal/` → :8081), arrête `essensys-cloud-backend`.

## Architecture nginx consolidée

- `location /api/` → `127.0.0.1:8080` (déjà dans `essensys.nginx`)
- Snippet `essensys-portal.conf` : **uniquement** `/portal/` (assets statiques)
- Plus de proxy `/api/portal/` ni `/api/gateway/` vers :8081

## Services systemd

| Mode | Services actifs |
|------|-----------------|
| Legacy | `essensys-backend` (:8080), `essensys-portal-backend` (:8081) |
| Consolidé | `essensys-cloud-backend` (:8080) |

## Dry-run

```bash
ansible-playbook -i inventory support-site.yml --check
```
