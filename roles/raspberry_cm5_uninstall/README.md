# raspberry_cm5_uninstall

Desinstallation de la **gateway Essensys CM5** (profil Ansible / Docker + reseau dual-NIC + NVMe).

## Usage

```bash
ansible-playbook uninstall.cm5.yml -i inventory.gateway \
  -e confirm_cm5_uninstall=true
```

Options destructives supplementaires :

```bash
# Retirer aussi l'entree fstab NVMe (demonte /mnt/nvme)
-e cm5_remove_nvme_fstab=true

# Effacer la partition NVMe (irreversible)
-e cm5_wipe_nvme_data=true

# Supprimer Docker apres desinstallation
-e cm5_remove_docker_packages=true
```

## Actions

1. Arret `docker compose` et suppression du compose file
2. Arret dnsmasq et configuration armoire
3. Demontage bind mounts NVMe (`/opt/data`, `/var/log/essensys`)
4. Suppression unites systemd-networkd gateway (`10-eth0.network`, `20-eth1.network`)
5. Execution du role `raspberry_uninstall` (services, Traefik, AdGuard, etc.)

## Non supprime par defaut

- Partition NVMe et label `essensys-data`
- Paquets Docker
- Utilisateur `essensys`
- OS Debian sur eMMC
