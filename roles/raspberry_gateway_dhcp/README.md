# raspberry_gateway_dhcp

Déploie `dnsmasq` comme serveur DHCP + DNS split sur le segment armoire (eth1).

- DHCP : émet des baux uniquement sur eth1, jamais sur eth0
- DNS : `mon.essensys.fr` (ou `gateway_armoire_hostname`) → `gateway_eth1_ip`
- DNS forwarding : toutes les autres requêtes → `gateway_upstream_dns`

## Variables principales

| Variable | Défaut | Description |
|---|---|---|
| `gateway_dhcp_range_start` | `10.0.1.100` | Début de la plage DHCP |
| `gateway_dhcp_range_end` | `10.0.1.200` | Fin de la plage DHCP |
| `gateway_dhcp_lease_time` | `12h` | Durée des baux |
| `gateway_dhcp_reservations` | `[]` | Réservations statiques (voir ci-dessous) |
| `gateway_upstream_dns` | `9.9.9.9` | DNS upstream pour le forwarding |
| `gateway_eth1_ip` | `10.0.1.1` | IP gateway vue depuis l'armoire |
| `gateway_armoire_hostname` | `mon.essensys.fr` | Hostname résolu vers eth1 |

## Format des réservations statiques

Dans `host_vars/<host>.yml` ou l'inventaire :

```yaml
gateway_dhcp_reservations:
  - mac: "aa:bb:cc:dd:ee:01"
    ip: "10.0.1.10"
    name: "armoire-principale"
  - mac: "aa:bb:cc:dd:ee:02"
    ip: "10.0.1.11"
    name: "equipement-bus-1"
```

## Conflits DNS port 53

Ce rôle vérifie à l'exécution qu'aucun autre processus (AdGuard, systemd-resolved)
n'écoute déjà sur `gateway_eth1_ip:53`. Si AdGuard est configuré avec `bind_host: 0.0.0.0`,
le rôle `raspberry_adguard` doit être appliqué **après** ce rôle avec `gateway_dual_nic: true`
pour restreindre son écoute DNS à eth0.

## Vérification

```bash
# Vérifier que dnsmasq écoute sur eth1 uniquement
ss -tlnup | grep ':53'

# Tester la résolution split-DNS depuis un client eth1
dig mon.essensys.fr @10.0.1.1

# Tester DHCP (depuis un client eth1, ou avec dhcping)
dhcping -s 10.0.1.1 -h aa:bb:cc:dd:ee:ff
```
