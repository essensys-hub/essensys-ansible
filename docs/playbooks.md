# Playbooks

This project contains several playbooks for different purposes.

## Main Deployment

### `support-site.yml`

This is the **primary playbook**. It performs a full deployment of the stack.

**Usage:**
```bash
ansible-playbook -i inventory support-site.yml
```

**What it does:**
1.  **System**: Installs all required packages and creates users.
2.  **Database**: Sets up PostgreSQL user and database.
3.  **Backend (legacy)**: `essensys-support-site` Go binary on `:8080` — when `cloud_backend_consolidated=false` or `cloud_backend_legacy_mode=true`.
4.  **Cloud backend (consolidated)**: `essensys-user-portal-backend` hub on `:8080` — when `cloud_backend_consolidated=true` and `cloud_backend_legacy_mode=false`. Voir [cloud-backend-migration.md](cloud-backend-migration.md).
5.  **Frontend**: Builds React app, installs Nginx site config.
6.  **Docs site** (`docs_site`): Build MkDocs from `essensys-doc`, deploy to `/opt/essensys/docs-site`, Nginx `docs.essensys.fr`.
7.  **Roadmap site** (`roadmap_site`): Build static site from `essensys-memory`, deploy to `/opt/essensys/roadmap-site`, Nginx `roadmap.essensys.fr`. Playbook dédié : `deploy-roadmap-site.yml`.
8.  **Portal backend (legacy)**: `:8081` — dual-stack only.
9.  **Portal frontend**: SPA `/portal/` static assets.
10. **Nginx portal snippet**: legacy split (`/api/portal/` → :8081) or consolidated (static `/portal/` only).

Variables: `cloud_backend_consolidated`, `cloud_backend_legacy_mode`, `portal_backend_port` (legacy, default 8081), `cloud_hub_public_url`.

### `deploy-roadmap-site.yml`

Deploy **roadmap.essensys.fr** (OpenSpec queue publique) + rebuild frontend avec blog `/blog`.

**Usage:**
```bash
ansible-playbook -i inventory deploy-roadmap-site.yml
```

**Roles:** `roadmap_site` (clone `essensys-memory`, build HTML statique, Nginx vhost) puis `frontend` (`prepare_blog_from_memory: true`).

**DoD:** `curl -sI https://roadmap.essensys.fr` et `curl -sI https://mon.essensys.fr/blog` → 200 (HTTPS si DNS + certbot OK).

---

## Raspberry Pi

### Installation Raspberry Pi (classique)

#### `install.raspberrypi.yml`

Installation complete pour Raspberry Pi **mono-NIC** (Nginx + Traefik + Backend + Frontend + AdGuard + Monitor + Docker Compose).

**Inventaire :** `inventory`

**Usage:**
```bash
ansible-playbook -i inventory install.raspberrypi.yml
```

---

### Gateway CM5 (double NIC + NVMe)

Documentation complete : **[install-gateway.md](install-gateway.md)**

#### `install.gateway.yml`

Installation **Gateway Essensys CM5** : NVMe, systemd-networkd dual-NIC, dnsmasq armoire, Avahi, stack Docker Compose identique au profil classique avec roles reseau/stockage supplementaires.

**Inventaire :** `inventory.gateway`

**Usage:**
```bash
ansible-playbook -i inventory.gateway install.gateway.yml
```

Variables obligatoires : `gateway_eth0_mac`, `gateway_eth1_mac` (voir inventaire).

#### `uninstall.cm5.yml`

Desinstallation de la stack Gateway CM5 (Docker, dnsmasq, units networkd gateway, bind mounts NVMe). **Ne supprime pas** l'OS ni le NVMe par defaut.

**Usage:**
```bash
ansible-playbook -i inventory.gateway uninstall.cm5.yml -e confirm_cm5_uninstall=true
```

#### `prepare.nixos-cm5.yml`

Preparation migration **NixOS** (clone flake, Nix, hardware genere, script eMMC). **N'installe pas** NixOS automatiquement.

**Usage:**
```bash
ansible-playbook -i inventory.gateway prepare.nixos-cm5.yml -e confirm_cm5_nixos_prep=true
```

---

### `update.raspberrypi.yml`

Mise a jour applicative (backend, frontend, config nginx/traefik, push status).

**Usage:**
```bash
ansible-playbook -i inventory update.raspberrypi.yml
# Gateway CM5 + LAN IAM :
ansible-playbook -i inventory.gateway update.raspberrypi.yml -e lan_iam_enabled=true
```

Variables clés (gateway) : `prometheus_port`, `alertmanager_port` et `wan_domain` sont calculées dans le playbook. Avec `lan_iam_enabled=true` : rôle `raspberry_postgresql`, migration `lan_users`, build frontend `VITE_LAN_IAM=true`.

### `uninstall.raspberrypi.yml`

Desinstallation complete. Requiert `confirm_uninstall=true`.

**Usage:**
```bash
ansible-playbook -i inventory uninstall.raspberrypi.yml -e "confirm_uninstall=true"
```

---

## HTTPS Enablement

These playbooks are used to enable SSL (HTTPS) via Let's Encrypt. Run them **after** the main deployment, as they require Nginx to be running.

### `enable-https-test.yml`

Enables HTTPS for the **Test Environment** (`test.essensys.fr`).

**Usage:**
```bash
ansible-playbook -i inventory enable-https-test.yml
```

### `enable-https-prod.yml`

Enables HTTPS for the **Production Environment** (`mon.essensys.fr`, `www.essensys.fr`, etc.).

**Usage:**
```bash
ansible-playbook -i inventory enable-https-prod.yml
```

---

## Quick Deployment

### `quick-deploy.yml`

A faster version of the deployment that **skips** system dependencies and database setup. It only updates the application code (Frontend + Backend).

**Use this when:** You just want to push a code update to an already running server.

**Usage:**
```bash
ansible-playbook -i inventory quick-deploy.yml
```

---

## Administrative Tools

### `promote-admin.yml`

Promotes a registered user to the **Admin** role in the database.

**Usage:**
1. Open `promote-admin.yml` and check the target email (default: `nicolas@rineau.eu`).
2. Run:
```bash
ansible-playbook -i inventory promote-admin.yml
```

> **Note:** The user must have already created an account (signed up) before you run this playbook.
