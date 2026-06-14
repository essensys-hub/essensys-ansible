# HTTPS de confiance pour `mon.essensys.local`

## Le problème

`mon.essensys.local` est résolu en LAN par **mDNS (Avahi)** et par une réécriture
**AdGuard** vers l'IP de la gateway. Mais **Let's Encrypt ne peut pas signer un
`.local`** (domaine non public, challenge ACME impossible). Sans configuration,
Traefik servait donc son **certificat auto-signé par défaut** sur ce domaine →
avertissement navigateur.

> Note : `mon.essensys.fr` accédé sur le LAN a, lui, un vrai certificat
> Let's Encrypt (Traefik `certResolver: letsencrypt` + réécriture AdGuard). C'est
> une alternative sans rien installer côté client.

## La solution (rôle `raspberry_traefik`)

1. Création d'une **CA locale** (`ca.key` / `ca.crt`, 10 ans) sur la gateway.
2. Signature d'un **certificat serveur** pour `mon.essensys.local`
   (SAN `DNS:mon.essensys.local` + IP de la gateway, validité < 825 j pour rester
   de confiance sur Apple). Régénéré automatiquement quand il expire dans < 30 j.
3. Dépôt de `dynamic/local-tls.yml` : Traefik le charge via le **provider file
   (`watch: true`)** → reload à chaud, **sans redémarrer le conteneur**. Le router
   `frontend-local` (`tls: {}`) sert alors ce certificat (match SNI).
4. **Distribution de la CA** :
   - téléchargement LAN : `https://mon.essensys.local/essensys-local-ca.crt`
     (déposée dans `{{ data_dir }}/frontend`, servie par le conteneur Nginx).
     En profil gateway, eth0:80 fait `return 444` → pas de HTTP côté LAN, le
     download passe donc par HTTPS, avec un **avertissement au premier accès**
     (normal : on télécharge justement la CA qui le fera disparaître) ;
   - installée dans le trust store de la gateway (`update-ca-certificates`) ;
   - rapatriée sur le contrôleur Ansible dans `files/local-ca/<host>.crt`.

Le seul geste **manuel restant** : installer cette CA une fois par appareil client.
La copie sur le contrôleur (`files/local-ca/<host>.crt`) est souvent le plus
pratique pour la diffuser (AirDrop, e-mail) sans passer par le téléchargement.

## (Re)déployer

```bash
cd essensys-ansible
ansible-playbook install.gateway.yml -i inventory.gateway --tags localtls
```

Le tag `localtls` ne lance que le bloc TLS local (idempotent, reload à chaud).
N.B. : `--tags traefik` redéploierait aussi les routes WAN, qui dépendent de
`wan_domain` (défini par un rôle antérieur) — à éviter en lancement isolé.

## Installer la CA sur un client

- **macOS** : double-clic sur `essensys-local-ca.crt` → Trousseau « système » →
  ouvrir le certif → Se fier → « Toujours approuver ».
- **iOS / iPadOS** : ouvrir l'URL dans Safari → installer le profil → Réglages →
  Général → VPN et gestion d'appareils → installer → puis **Réglages → Général →
  Infos → Réglages des certificats de confiance** → activer la confiance.
- **Linux** : `sudo cp essensys-local-ca.crt /usr/local/share/ca-certificates/ &&
  sudo update-ca-certificates`.
- **Windows** : `certutil -addstore -f Root essensys-local-ca.crt` (admin).
- **Android** : Paramètres → Sécurité → Chiffrement → Installer un certificat → CA.
- **Firefox** : possède son propre magasin → Paramètres → Certificats → Importer,
  cocher « confiance pour identifier des sites web ».

## Variables (rôle `raspberry_traefik`)

| Variable | Défaut | Rôle |
|---|---|---|
| `traefik_local_tls_enabled` | `true` | Active toute la mécanique |
| `traefik_local_domain` | `mon.essensys.local` | Domaine à certifier |
| `traefik_ca_days` | `3650` | Validité de la CA |
| `traefik_leaf_days` | `820` | Validité du cert serveur |
| `traefik_leaf_renew_days` | `30` | Seuil de régénération auto |
| `traefik_publish_ca` | `true` | Publier la CA en téléchargement LAN |
| `traefik_install_ca_on_gateway` | `true` | Installer la CA sur la gateway |
| `traefik_fetch_ca_to_controller` | `true` | Copier la CA sur le contrôleur |

## Rotation / révocation

Pour forcer une nouvelle CA : supprimer `…/traefik/certs/ca.*` sur la gateway et
relancer le playbook (puis réinstaller la nouvelle CA sur les clients). Pour
juste renouveler le cert serveur : supprimer `local.crt`, relancer.
