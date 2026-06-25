# Gestion des secrets Essensys (SOPS + age)

Documentation canonique pour les secrets de déploiement **cloud OVH** et **gateways CM5**.  
OpenSpec : `essensys-memory/openspec/changes/essensys-secrets-sops-migration-2026-06-028/`

> **Ne pas confondre** avec le vault Obsidian `essensys-memory/` (brain projet).

## Vue d'ensemble

| Couche | Fichier secrets | Chiffrement | Runtime |
|--------|-----------------|-------------|---------|
| Cloud OVH | `secrets/cloud/essensys.sops.yaml` | SOPS + age | `.env` systemd (`/opt/essensys/cloud-backend/.env`) |
| Gateway CM5 | `host_vars/<hostname>/secrets.sops.yaml` | SOPS + age (phase 2) | `config.yaml` cloudsync |

Ansible charge les secrets via le rôle **`sops_load`** (`community.sops` lookup) avant les rôles applicatifs.

## Inventaire secrets cloud (MVP)

| Variable SOPS | Service | Template / rôle |
|---------------|---------|-----------------|
| `portal_db_password`, `portal_db_name` | PostgreSQL, cloud-backend | `cloud-backend.env.j2`, `database`, `import_machines.yml` |
| `portal_jwt_secret` | cloud-backend JWT | `cloud-backend.env.j2` |
| `vault_admin_token`, `vault_admin_emails` | API admin | `cloud-backend.env.j2` |
| `vault_google_*`, `vault_apple_*` | OAuth | `cloud-backend.env.j2` |
| `vault_apple_key_content` | OAuth Apple (optionnel) | `cloud_backend/tasks/apple_oauth_key.yml` → `/opt/essensys/secrets/apple/` |
| `vault_smtp_*` | Newsletter SMTP | `cloud-backend.env.j2` |
| `vault_newrelic_license_key` | APM Go | `cloud-backend.env.j2` |
| `vault_newrelic_browser_license_key` | Build Vite NR | `roles/frontend/tasks/main.yml` |
| `vault_newrelic_api_key` | Alertes NR API | `newrelic_alerts`, `newrelic_deployment` |
| `cloud_frontend_url` | Redirects OAuth | SOPS cloud |

## Inventaire secrets gateway (phase 2)

| Variable | Fichier cible |
|----------|---------------|
| `cloud_gateway_id`, `cloud_gateway_token`, `cloud_gateway_machine_id` | `config.yaml` via `raspberry_backend/tasks/cloud_sync.yml` |
| `cloud_gateway_eth0_mac`, `cloud_gateway_eth1_mac` | inventaire / SOPS gateway |

Exemple : `host_vars/example/secrets.sops.yaml.example`

## Bootstrap opérateur

### Prérequis

```bash
brew install sops age          # macOS
ansible-galaxy collection install -r requirements.yml
./scripts/sops-init.sh         # génère ~/.config/sops/age/keys.txt si absent
export SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"
```

La **clé publique age** est dans `.sops.yaml`. La clé **privée** ne doit jamais être commitée.

### Édition secrets cloud

```bash
cd essensys-ansible
sops secrets/cloud/essensys.sops.yaml
```

### Migration depuis Ansible Vault (legacy)

```bash
ansible-vault view group_vars/essensys/vault.yml > /tmp/vault-plain.yaml
sops --encrypt --age "$(age-keygen -y "$SOPS_AGE_KEY_FILE")" /tmp/vault-plain.yaml > secrets/cloud/essensys.sops.yaml
shred -u /tmp/vault-plain.yaml   # macOS : rm -P
```

## Déploiement

Les playbooks cloud incluent `sops_load` en tête :

- `support-site.yml`
- `setup-newrelic-alerts.yml`

```bash
export SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"
ansible-playbook -i inventory support-site.yml --check --diff
ansible-playbook -i inventory support-site.yml
```

Gateway (phase 2) : `install.gateway.yml` charge `host_vars/<hostname>/secrets.sops.yaml` si présent.

## Rotation clés age

1. Générer nouvelle paire : `age-keygen -o keys-new.txt`
2. Ajouter la nouvelle pubkey dans `.sops.yaml` `creation_rules`
3. Re-chiffrer : `sops updatekeys secrets/cloud/essensys.sops.yaml`
4. Révoquer l'ancienne clé privée après validation deploy

## Rollback (Ansible Vault temporaire)

Si SOPS bloque un déploiement urgent :

1. Restaurer `group_vars/essensys/vault.yml` local (backup chiffré Ansible Vault)
2. Retirer temporairement le rôle `sops_load` des playbooks
3. Déployer avec `ansible-vault` comme avant
4. Corriger SOPS puis réactiver `sops_load`

## Validation CI / locale

```bash
export SOPS_AGE_KEY_FILE=...
./scripts/verify-sops.sh
```

Le script vérifie la metadata SOPS, un decrypt test, et l'absence de secrets clairs dans `git diff`.

## Parité Ansible vs NixOS (sops-nix)

| Aspect | Ansible (CM5) | NixOS (`essensys-gateway-nixos`) |
|--------|---------------|----------------------------------|
| Format fichier | `host_vars/*/secrets.sops.yaml` | Même fichiers SOPS source |
| Chiffrement | age (`.sops.yaml`) | age (identique) |
| Chargement | rôle `sops_load` | sops-nix / agenix |
| Cloud hub | `secrets/cloud/essensys.sops.yaml` | N/A (cloud reste Ansible) |

Objectif : **un seul format SOPS + age** pour éviter deux conventions de secrets edge.

## Sécurité

- `no_log: true` sur toutes les tâches SOPS Ansible
- Permissions `.env` on-host : `0600`, owner `essensys`
- Clé Apple `.p8` : `/opt/essensys/secrets/apple/AuthKey.p8` si `vault_apple_key_content` défini dans SOPS
- Jamais de secret clair dans Git (review PR = diff chiffré SOPS uniquement)

## Voir aussi

- [backup-synology.md](backup-synology.md) — sauvegarde quotidienne secrets → NAS Synology (rclone)
- [newrelic.md](newrelic.md) — clés NR dans SOPS cloud
- [install-gateway.md](install-gateway.md) — tokens `cloud_gateway_*`
- Brain : [[Secrets Management]], [[Essensys Ansible]], [[Gateway PKI]]
