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
3.  **Backend**: Clones source, builds Go binary, configures Systemd.
4.  **Frontend**: Builds React app, installs Nginx site config.
5.  **Portal backend** (`portal_backend`): `essensys-user-portal-backend` on port 8081.
6.  **Portal frontend** (`portal_frontend`): SPA `/portal/` static assets.
7.  **Portal nginx** (`portal_nginx`): Routes `/api/portal/`, `/api/gateway/`.

Variables: `portal_backend_repo`, `portal_frontend_repo`, `portal_backend_port` (default 8081), `cloud_hub_public_url`.

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
```

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
