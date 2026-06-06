# raspberry_gateway_nvme

Prépare le SSD NVMe du CM5 et redirige les chemins à forte écriture (logs, données applicatives)
vers le NVMe via des bind mounts, afin de préserver l'eMMC.

## Prérequis matériels (étapes manuelles avant l'Ansible)

### 1. Activer l'interface PCIe / NVMe sur le CM5

Editer `/boot/firmware/config.txt` :

```ini
# Activer PCIe externe (M.2 NVMe via IO Board)
dtparam=pciex1
```

Redémarrer et vérifier :

```bash
lspci | grep -i nvme
ls /dev/nvme*
```

### 2. (Optionnel) Configurer le BOOT_ORDER EEPROM

Si vous souhaitez booter depuis le NVMe (non requis pour ce rôle, l'OS reste sur eMMC) :

```bash
sudo raspi-config  # → Advanced → Boot Order → NVMe/USB
# ou manuellement :
sudo rpi-eeprom-config --edit
# BOOT_ORDER=0xf416  # NVMe first, then SD/eMMC
```

## Variables principales

| Variable | Défaut | Description |
|---|---|---|
| `gateway_nvme_device` | `/dev/nvme0n1` | Périphérique NVMe cible |
| `essensys_nvme_mount` | `/mnt/nvme` | Point de montage principal |
| `gateway_nvme_bind_mounts_enabled` | `true` | Activer les bind mounts |
| `gateway_nvme_bind_mounts` | voir defaults | Liste `{src, dest}` des bind mounts |

## Règle de placement des données

| Support | Contenu |
|---|---|
| **eMMC** (`mmcblk0`) | OS, paquets apt, images Docker, config statique, bootloader |
| **NVMe** (`nvme0n1`) | `data_dir` (/opt/data), logs (/var/log/essensys), tout ce qui croît |

## Commandes de validation post-install

```bash
# Vérifier le partitionnement
lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT

# Vérifier les montages
findmnt /mnt/nvme
findmnt /opt/data

# Vérifier l'espace disque par support
df -h /mnt/nvme /opt/data /var/log/essensys /

# Test d'écriture sur NVMe
dd if=/dev/zero of=/opt/data/.nvme_write_test bs=1M count=10 && rm /opt/data/.nvme_write_test
```

## Mode dégradé (NVMe absent ou défaillant)

Mettre `gateway_nvme_bind_mounts_enabled: false` dans l'inventaire.
Le NVMe sera monté (si présent) mais les données resteront sur l'eMMC.
Un avertissement sera affiché à chaque run.

## Rollback

```bash
# Démonter les bind mounts
sudo umount /opt/data /var/log/essensys

# Supprimer les entrées fstab correspondantes
sudo nano /etc/fstab  # retirer les lignes "bind" et UUID NVMe

# Démonter le NVMe
sudo umount /mnt/nvme

# Restaurer le drop-in Docker
sudo rm /etc/systemd/system/docker.service.d/after-nvme.conf
sudo systemctl daemon-reload
```
