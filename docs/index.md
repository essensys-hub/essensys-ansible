# Essensys Ansible

Welcome to the **Essensys Ansible** project documentation. This repository contains the Infrastructure-as-Code (IaC) to deploy and maintain the Essensys Support Site (`essensys-support-site`) on Ubuntu VPS servers.

## Overview

This project uses **Ansible** to automate:
- **System Setup**: Installing dependencies (Nginx, Go, Node.js, PostgreSQL).
- **Backend Deployment**: Building and running the Go backend as a Systemd service.
- **Frontend Deployment**: Building and serving the React application via Nginx.
- **HTTPS Configuration**: Securing the site with Let's Encrypt certificates.

## Prerequisites

- **Ansible**: Must be installed on your local machine (`brew install ansible` on macOS).
- **SSH Access**: You must have SSH access to the target servers (e.g., `test.essensys.fr`).

## Quick Start

1.  **Check Connection**:
    ```bash
    ansible -i inventory essensys -m ping
    ```
2.  **Deploy Site**:
    ```bash
    ansible-playbook -i inventory support-site.yml
    ```
