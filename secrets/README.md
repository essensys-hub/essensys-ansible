# Secrets Essensys (SOPS + age)

Les secrets cloud et gateway sont chiffrés avec [SOPS](https://github.com/getsops/sops) et [age](https://github.com/FiloSottile/age).

## Fichiers

| Chemin | Périmètre |
|--------|-----------|
| `secrets/cloud/essensys.sops.yaml` | Hub OVH (`mon.essensys.fr`) — MVP |
| `secrets/operator/backup.syno.sops.yaml` | Config backup NAS Synology (rclone) |
| `secrets/cloud/android-release.sops.yaml` | Clé de signature des APK release Android (keystore PKCS12 base64, mots de passe, alias `essensys-android`) |
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

## Clé de signature Android

`secrets/cloud/android-release.sops.yaml` contient le keystore de release de l'app Android. Il a été créé le 2026-10-09 (`android-portal-refresh-2026-10-002`, RSA 4096, valable 30 ans) et se déchiffre avec `.age/keys.txt`.

- **Empreinte SHA-256 du certificat de signature** (publique, à communiquer pour vérifier les APK) :
  `A0:96:0E:61:21:9C:E1:0A:40:81:92:C0:7E:E3:9F:7C:B2:0B:41:DB:BD:7F:61:C7:B0:4A:7E:D5:22:4D:D2:B2`
- **Copies dans GitHub Actions** : les secrets du dépôt `essensys-hub/essensys-android-phone-apps` (`ANDROID_KEYSTORE_B64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`) en sont des copies. Utilisés par le workflow `release.yml`.
- **Ne jamais perdre cette clé.** Toute mise à jour de l'app doit être signée avec la même clé ; sans elle, les clients doivent désinstaller puis réinstaller.
- **Republier les secrets CI après une rotation** :

```bash
export SOPS_AGE_KEY_FILE=".age/keys.txt"
for k in keystore_b64:ANDROID_KEYSTORE_B64 store_password:ANDROID_KEYSTORE_PASSWORD key_alias:ANDROID_KEY_ALIAS key_password:ANDROID_KEY_PASSWORD; do
  sops -d --extract "[\"android_release_${k%%:*}\"]" secrets/cloud/android-release.sops.yaml \
    | gh secret set "${k#*:}" --repo essensys-hub/essensys-android-phone-apps
done
```

