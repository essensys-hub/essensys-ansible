# Roles

The project is structured into reusable Ansible roles.

## `common`

Handles the base system configuration.

- **Tasks**:
    - Installs APT packages: `git`, `nginx`, `curl`, `postgresql`, `certbot`, etc.
    - Installs **Go** (via curl).
    - Installs **Node.js** (via Nodesource script).
    - Creates the `essensys` system user.
    - Creates directory structure: `/opt/essensys/{backend,frontend,maintenance}`.

## `database`

Manages the PostgreSQL database.

- **Tasks**:
    - Ensures PostgreSQL service is running.
    - Creates the `essensys` database user.
    - Creates the `essensys_db` database.

## `backend`

Deploys the Go backend application.

- **Tasks**:
    - Clones the code from GitHub (`essensys-support-site`).
    - Builds the Go binary (`cmd/server`).
    - Installs the binary to `/opt/essensys/backend/server`.
    - Configures `.env` file.
    - Installs and enables `essensys-backend.service` (Systemd).

## `frontend`

Deploys the React frontend application.

- **Tasks**:
    - Clones the code from GitHub.
    - Installs NPM dependencies.
    - Builds the production bundle (`npm run build`).
    - Copies artifacts to `/opt/essensys/frontend/dist`.
    - Deploys the maintenance page.
    - Installs `essensys.nginx` configuration to `/etc/nginx/sites-available`.
    - Reloads Nginx.

---

## Raspberry Pi roles

These roles are used by `install.raspberrypi.yml` and `update.raspberrypi.yml`.

## `raspberry_common`

- **Tasks**:
    - Installs APT packages for Raspberry Pi.
    - Installs **Go** and **Node.js**.
    - Creates the `essensys` user and directories.
    - Ensures Redis is running.

## `raspberry_backend`

- **Tasks**:
    - Clones `essensys-server-backend`.
    - Builds the Go binary and deploys it.
    - Creates `config.yaml`.
    - Installs and enables systemd service.

## `raspberry_frontend`

- **Tasks**:
    - Clones `essensys-server-frontend`.
    - Builds the frontend.
    - Deploys assets to `/opt/essensys/frontend`.

## `raspberry_nginx`

- **Tasks**:
    - Deploys nginx configs and log formats.
    - Enables local and internal sites.
    - Reloads nginx.

## `raspberry_traefik`

- **Tasks**:
    - Installs Traefik binary.
    - Deploys static and dynamic configuration.
    - Installs block service and systemd units.

## `raspberry_adguard`

- **Tasks**:
    - Installs AdGuard Home.
    - Deploys configuration and rewrite.

## `raspberry_monitor`

- **Tasks**:
    - Installs monitoring UI and autologin setup.

## `raspberry_logrotate`

- **Tasks**:
    - Installs logrotate rules for Essensys logs.

## `raspberry_push_status`

- **Tasks**:
    - Installs push status script and timer.

## `raspberry_uninstall`

- **Tasks**:
    - Stops services and removes files.
    - Optional removal of nginx/redis/user.
