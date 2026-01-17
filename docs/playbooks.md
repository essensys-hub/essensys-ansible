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
