# raspberry_gateway_network

Configure dual-NIC networking on the CM5 gateway using systemd-networkd.

- **eth0** : LAN (client DHCP vers le routeur amont)
- **eth1** : segment armoire (IP statique, DHCP serveur via le rôle `raspberry_gateway_dhcp`)

## Étapes non-automatisables (à faire avant le premier `ansible-playbook`)

### 1. Flash eMMC (premier démarrage)

Sur un poste avec `rpiboot` installé :

```bash
# Mode USB-OTG du CM5 (jumper BOOT sur la IO Board si besoin)
sudo rpiboot
# Puis utiliser Raspberry Pi Imager pour flasher Pi OS Bookworm Lite sur /dev/sdX
```

### 2. Activer PCIe / NVMe sur CM5

Editer `/boot/firmware/config.txt` sur le CM5 **avant** d'exécuter l'Ansible :

```ini
# Activer l'interface PCIe externe (nécessaire pour le NVMe)
dtparam=pciex1
# ou sur certaines IO boards :
# dtparam=pcie-32bit-dma=on
```

Puis flasher l'EEPROM avec le boot order NVMe si souhaité (`raspi-config` → Advanced → Boot Order, ou `rpi-eeprom-config`).

### 3. Identifier les adresses MAC

```bash
ip link show eth0 | awk '/ether/{print $2}'
ip link show eth1 | awk '/ether/{print $2}'
```

Renseigner ces valeurs dans l'inventaire ou `host_vars/<host>.yml` :

```yaml
gateway_eth0_mac: "dc:a6:32:xx:xx:xx"
gateway_eth1_mac: "dc:a6:32:xx:xx:xx"
```

## Variables principales

| Variable | Défaut | Description |
|---|---|---|
| `gateway_dual_nic` | `false` | Activer le profil double NIC |
| `gateway_eth0_mac` | `""` | MAC de eth0 (obligatoire) |
| `gateway_eth1_mac` | `""` | MAC de eth1 (obligatoire) |
| `gateway_eth1_ip` | `10.0.1.1` | IP statique eth1 |
| `gateway_eth1_prefix` | `24` | Masque CIDR eth1 |
| `gateway_eth0_ip` | `""` | IP eth0 (auto-détecté si vide) |
| `gateway_armoire_hostname` | `mon.essensys.fr` | Hostname résolu vers eth1 IP |

## Rollback

```bash
# Restaurer les fichiers réseau sauvegardés
sudo cp /etc/systemd/network/10-eth0.network.bak /etc/systemd/network/10-eth0.network
sudo cp /etc/systemd/network/20-eth1.network.bak /etc/systemd/network/20-eth1.network
sudo systemctl restart systemd-networkd
```
