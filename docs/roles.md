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

## `raspberry_postgresql`

- **Tasks** (when `lan_iam_enabled` / `gateway_db_enabled`):
    - Installs PostgreSQL + `python3-psycopg2`.
    - Creates user/database `essensys` / `essensys_db`.
    - Injects `database:` block in `config.yaml` backend.

## `raspberry_backend`

- **Tasks**:
    - Dedupes Ansible-managed YAML blocks in `config.yaml`.
    - Clones `essensys-server-backend`.
    - Builds the Go binary and deploys it.
    - Configures `lan_iam`, cloud sync, UniFi blocks (`tasks/unifi.yml`, also used by the UniFi doorbell, Feature `sonnette-unifi-2026-11-007`; the API key is never shown in `--diff`).
    - Creates `/opt/data/light-names` (owner `service_user`, mode `0750`) and manages the `light_names.path` block in `config.yaml` (custom light names, Feature `noms-lumieres-2026-11-004`).
    - Applies migration `003_lan_users` when LAN IAM enabled.
    - Installs and enables systemd service.

!!! warning "Noms de lumieres : recreer le conteneur"
    `raspberry_compose` monte `/opt/data/light-names` en ecriture sur `/var/lib/essensys/names`
    dans `essensys-backend` (le reste du conteneur reste en lecture seule). Un nouveau montage
    n'est pris en compte qu'a la **recreation** du conteneur : `install.gateway.yml` le fait
    (`up -d --force-recreate`) ; sinon lancer
    `docker compose -f /opt/data/docker-compose.yml up -d --force-recreate essensys-backend`.
    Un simple `docker restart` ne suffit pas (les routes de noms repondent alors 503 `names_unavailable`).
    Le fichier `light-names.json` est sauvegarde avec `/opt/data`.

## `raspberry_frontend`

- **Tasks**:
    - With LAN IAM: git clone + `VITE_LAN_IAM=true npm run build`.
    - Otherwise: Docker image pull + extract static files.

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
