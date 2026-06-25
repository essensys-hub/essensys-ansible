# Backup Essensys → Synology (rclone)

Backup quotidien du **monorepo complet** `/Users/nrineau/ESSENSYS` (~40 dépôts) vers le NAS Synology.

| Paramètre | Valeur |
|-----------|--------|
| NAS | `192.168.1.61` (SOPS) |
| Partage | `BACKUP-ESSENSYS` |
| Compte | `nrineau` |
| Source | `backup_monorepo_root` → `/Users/nrineau/ESSENSYS` |
| Horaire | **02:00** (launchd macOS) |
| Config | `secrets/operator/backup.syno.sops.yaml` |

## Contenu sauvegardé

| Source | Destination NAS |
|--------|-----------------|
| **`/Users/nrineau/ESSENSYS/**`** (monorepo) | `BACKUP-ESSENSYS/essensys/<hostname>/daily/YYYY-MM-DD/ESSENSYS/` |
| Fichiers gitignored inclus | `.age/`, `vault.yml`, `config/.env`, `config/rclone.conf` |
| `backup_extra_paths` (SOPS) | `.../daily/YYYY-MM-DD/extra/` |

**Exclusions par défaut** (`config/backup-rclone-exclude.txt`) : `node_modules`, caches build, `.cursor/projects`, etc. — **pas** les `.git` (historique conservé).

Premier run : ~10–14 Go, **plusieurs heures** en SMB. Runs suivants : incrémental (rclone copy).

Rétention : **30 jours** de snapshots `daily/`.

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
| `backup_monorepo_root` | Racine à copier (défaut `/Users/nrineau/ESSENSYS`) |
| `backup_rclone_exclude_file` | Exclusions rclone (défaut `config/backup-rclone-exclude.txt`) |
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
