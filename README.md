# essensys-ansible

## Raspberry Pi

Les scripts `install.sh`, `update.sh`, `uninstall.sh` du projet
`essensys-raspberry-install` sont remplaces par des playbooks Ansible.

### Playbooks

- `install.raspberrypi.yml` : installation complete (Nginx, Traefik, Backend,
  Frontend, AdGuard, Monitor, logrotate, push status).
- `update.raspberrypi.yml` : mise a jour applicative (backend, frontend,
  config nginx/traefik, push status).
- `uninstall.raspberrypi.yml` : desinstallation complete (requiert
  confirmation explicite).

### Usage

```bash
ansible-playbook -i inventory install.raspberrypi.yml
ansible-playbook -i inventory update.raspberrypi.yml
ansible-playbook -i inventory uninstall.raspberrypi.yml -e "confirm_uninstall=true"
```

### Notes

- Le domaine WAN est lu dans `/home/essensys/domain.txt` (defaut:
  `essensys.acme.com`).
- Pour activer Let's Encrypt en staging :
  `-e "use_staging=true"`.
- Pour changer l'email ACME :
  `-e "acme_email=ton@email"`.
- Le script de creation htpasswd est installe en
  `/usr/local/bin/generate-htpasswd-essensys.sh`.