# Backup Essensys → Synology (rclone)

Backup quotidien des **secrets opérateur** (SOPS, clé age, vault legacy, `.env`) vers le NAS Synology.

| Paramètre | Valeur |
|-----------|--------|
| NAS | `192.168.1.61` (dans SOPS) |
| Partage | `BACKUP-ESSENSYS` |
| Compte | `nrineau` |
| Horaire | **02:00** chaque jour (launchd macOS) |
| **Config Synology** | **`secrets/operator/backup.syno.sops.yaml`** (SOPS + age) |

## Contenu sauvegardé

| Source locale | Destination remote |
|---------------|-------------------|
| `secrets/` (SOPS cloud + operator) | `essensys/<hostname>/daily/YYYY-MM-DD/essensys-ansible/secrets/` |
| `.age/` (clé privée age) | idem |
| `group_vars/essensys/vault.yml` | idem (si présent) |
| `config/.env` | idem (si présent) |
| `backup_extra_paths` (SOPS) | `essensys/.../extra/` |

Rétention par défaut : **30 jours** de snapshots `daily/`.

## Installation (une fois)

```bash
cd essensys-ansible
export SOPS_AGE_KEY_FILE=".age/keys.txt"

# Si le fichier chiffré n'existe pas encore :
cp secrets/operator/backup.syno.sops.yaml.example secrets/operator/backup.syno.sops.yaml
sops --encrypt --in-place secrets/operator/backup.syno.sops.yaml

# Renseigner le mot de passe Synology (syno_pass) :
sops secrets/operator/backup.syno.sops.yaml

./scripts/backup-syno-init.sh    # crée config/rclone.conf depuis SOPS
./scripts/backup-to-syno.sh      # test manuel
./scripts/install-backup-schedule.sh   # launchd 02:00
```

### Clés SOPS (`backup.syno.sops.yaml`)

| Clé | Description |
|-----|-------------|
| `syno_host` | IP NAS (ex. `192.168.1.61`) |
| `syno_user` | Compte SMB |
| `syno_share` | Partage (ex. `BACKUP-ESSENSYS`) |
| `syno_pass` | Mot de passe SMB |
| `rclone_remote` | Nom remote rclone (défaut `syno-essensys`) |
| `backup_remote_base` | Dossier racine sur le partage |
| `backup_retention_days` | Rétention snapshots |
| `backup_extra_paths` | Chemins extra (`:` séparés) |

## Commandes utiles

```bash
export SOPS_AGE_KEY_FILE=".age/keys.txt"

# Éditer config Synology
sops secrets/operator/backup.syno.sops.yaml

# Backup manuel
./scripts/backup-to-syno.sh

# Forcer run launchd
launchctl kickstart -k gui/$(id -u)/com.essensys.syno-backup

# Logs
tail -f ~/Library/Logs/essensys-backup/backup-$(date +%Y%m%d).log
```

## Prérequis

- Mac sur le **même LAN** que le Synology à 02:00 (ou VPN permanent)
- `brew install rclone sops age`
- Clé age : `.age/keys.txt` (même clé que secrets cloud)
- Droits **lecture/écriture** sur `BACKUP-ESSENSYS` pour `nrineau`

## Sécurité

- Identifiants Synology dans **SOPS** (versionné chiffré) — pas de `.env` en clair
- `config/rclone.conf` reste **gitignored** (mot de passe obscurci rclone)
- Le snapshot NAS contient des secrets **déchiffrés** — ACL strictes sur le partage
- Voir [secrets.md](secrets.md) et [[Secrets Management]]

## Désinstallation planification

```bash
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.essensys.syno-backup.plist
rm ~/Library/LaunchAgents/com.essensys.syno-backup.plist
```
