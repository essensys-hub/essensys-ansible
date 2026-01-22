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

---

## Raspberry Pi

### `install.raspberrypi.yml`

Installation complete pour Raspberry Pi (Nginx + Traefik + Backend + Frontend + AdGuard + Monitor).

**Usage:**
```bash
ansible-playbook -i inventory install.raspberrypi.yml
```

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
