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
