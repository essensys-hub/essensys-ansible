# raspberry_cm5_nixos

Prepare une **CM5 Essensys** pour une installation **NixOS** (flake `essensys-raspberry-gateway`, branche `nixos`).

## Ce que fait le role (sans detruire l'eMMC par defaut)

1. Detecte MAC/IP eth0 et eth1
2. Verifie NVMe (`essensys-data`) — **conserve les donnees** par defaut
3. Clone le depot gateway (branche `nixos`) dans `/opt/essensys-nixos`
4. Clone `essensys-nginx` en sibling pour le flake input
5. Genere `hardware-cm5.generated.nix` avec les valeurs CM5
6. Installe **Nix** + active flakes
7. Deploie `/usr/local/sbin/essensys-prepare-nixos-mmc.sh` pour repartition **offline** de l'eMMC

## Usage

```bash
ansible-playbook prepare.nixos-cm5.yml -i inventory.gateway \
  -e confirm_cm5_nixos_prep=true
```

Migration depuis Debian (desinstaller d'abord la stack Ansible) :

```bash
ansible-playbook uninstall.cm5.yml -i inventory.gateway -e confirm_cm5_uninstall=true
ansible-playbook prepare.nixos-cm5.yml -i inventory.gateway -e confirm_cm5_nixos_prep=true
```

## Partitionnement eMMC (manuel, boot recovery)

**Ne jamais** lancer la repartition eMMC depuis Debian actif sur la meme eMMC.

1. Boot recovery (USB/SD)
2. `sudo /usr/local/sbin/essensys-prepare-nixos-mmc.sh`
3. Monter la root ext4 et executer `nixos-install --flake /opt/essensys-nixos#gateway-cm5`

Ou activer (a vos risques) : `-e cm5_nixos_run_emmc_repartition=true` — le script refuse si l'eMMC est le device de boot.

## Layout eMMC cible

| Partition | Taille | FS | Label |
|-----------|--------|-----|-------|
| p1 | 512 MiB | vfat | boot |
| p2 | reste | ext4 | nixos |

NVMe : partition unique `essensys-data` — **donnees** (`/mnt/nvme`, `/opt/data`) preservees pour NixOS.

## Variables

| Variable | Defaut | Description |
|----------|--------|-------------|
| `cm5_nixos_checkout_dir` | `/opt/essensys-nixos` | Clone du flake |
| `cm5_nixos_branch` | `nixos` | Branche git |
| `cm5_nixos_preserve_nvme_data` | `true` | Ne pas formater NVMe |
| `cm5_nixos_run_emmc_repartition` | `false` | Repartition eMMC auto (danger) |
