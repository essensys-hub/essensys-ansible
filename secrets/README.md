# Secrets Essensys (SOPS + age)

Les secrets cloud et gateway sont chiffrés avec [SOPS](https://github.com/getsops/sops) et [age](https://github.com/FiloSottile/age).

## Fichiers

| Chemin | Périmètre |
|--------|-----------|
| `secrets/cloud/essensys.sops.yaml` | Hub OVH (`mon.essensys.fr`) — MVP |
| `secrets/operator/backup.syno.sops.yaml` | Config backup NAS Synology (rclone) |
| `host_vars/<hostname>/secrets.sops.yaml` | Passerelle CM5 (phase 2) |

## Prérequis opérateur

```bash
brew install sops age   # macOS
export SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"
# ou copier la clé depuis bootstrap : scripts/sops-init.sh
```

Installer la collection Ansible :

```bash
ansible-galaxy collection install -r requirements.yml
```

## Édition

```bash
cd essensys-ansible
export SOPS_AGE_KEY_FILE=".age/keys.txt"   # ou ~/.config/sops/age/keys.txt
sops secrets/cloud/essensys.sops.yaml      # chemin exact — pas essensys.sops.yaml à la racine
```

> **Attention :** `sops essensys.sops.yaml` depuis la racine du dépôt ouvre un **nouveau fichier vide** avec le template « Welcome to SOPS! » (dans `/tmp/…`). Ce n’est **pas** le fichier prod. Le bon chemin est toujours **`secrets/cloud/essensys.sops.yaml`**.

Pour vérifier le contenu sans éditeur :

```bash
export SOPS_AGE_KEY_FILE=".age/keys.txt"
sops -d secrets/cloud/essensys.sops.yaml | grep -E '^portal_|^vault_'
```

Documentation complète : [docs/secrets.md](../docs/secrets.md).
