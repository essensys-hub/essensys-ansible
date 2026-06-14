# Essensys Ansible

Documentation du dépôt **essensys-ansible** : déploiement automatisé du site support, des **Raspberry Pi / CM5** Essensys et de la **Gateway CM5** (double NIC + NVMe).

## Vue d'ensemble

Ansible automatise notamment :

- **Site support** (`support-site.yml`) : Nginx, Go, PostgreSQL sur VPS.
- **Raspberry classique** ([`install.raspberrypi.yml`](playbooks.md#installation-raspberry-pi-classique)) : stack Essensys mono-NIC, Docker Compose.
- **Gateway CM5** ([guide complet](install-gateway.md)) : CM5, eth0/eth1, NVMe, dnsmasq armoire, mDNS, TLS local `.local`.
- **HTTPS** : Let's Encrypt (WAN) et CA locale (`mon.essensys.local`) — voir [tls-local-domain.md](tls-local-domain.md).

## Prérequis

- **Ansible** sur le poste contrôleur (`brew install ansible` sur macOS).
- **SSH** vers la cible (`ansible_user`, clé ou mot de passe).

## Démarrage rapide

### Site support (VPS)

```bash
ansible -i inventory essensys -m ping
ansible-playbook -i inventory support-site.yml
```

### Gateway CM5

```bash
ansible -i inventory.gateway raspberrypi -m ping
ansible-playbook -i inventory.gateway install.gateway.yml
```

Guide détaillé : **[Installation Gateway CM5](install-gateway.md)**.

### Raspberry Pi (classique)

```bash
ansible-playbook -i inventory install.raspberrypi.yml
```

Voir [Playbooks — installation classique](playbooks.md#installation-raspberry-pi-classique).
