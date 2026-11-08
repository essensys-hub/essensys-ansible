# Notifications push de la sonnette (FCM et APNs)

Feature `sonnette-plages-push-2026-11-008` (essensys-feature-lifecycle#61, essensys-ansible#19).
Le backend cloud envoie une notification quand la sonnette est appuyée : **FCM** (Firebase Cloud Messaging) pour Android, **APNs** (Apple) pour l'iPhone. Chaque fournisseur est **facultatif** : sans ses clés, le cloud accepte l'appui, n'envoie rien et journalise `push_unavailable` une fois.

Ce document ne contient aucune valeur réelle. Les valeurs vont **uniquement** dans `secrets/cloud/essensys.sops.yaml` (`sops secrets/cloud/essensys.sops.yaml`, voir [secrets.md](secrets.md)).

## Clés SOPS et variables du backend

| Clé SOPS | Variable du backend | Fournisseur |
|---|---|---|
| `fcm_project_id` | `FCM_PROJECT_ID` | FCM |
| `fcm_service_account_json` | `FCM_SERVICE_ACCOUNT_JSON` (JSON complet, multi-ligne accepté) | FCM |
| `apns_key_p8` | `APNS_KEY_P8` (contenu PEM de la clé `.p8`, multi-ligne) | APNs |
| `apns_key_id` | `APNS_KEY_ID` | APNs |
| `apns_team_id` | `APNS_TEAM_ID` | APNs |
| `apns_bundle_id` | `APNS_BUNDLE_ID` (défaut côté serveur : `essensys.essensys-iphone`) | APNs |
| `apns_env` | `APNS_ENV` : `production` (défaut) ou `development` | APNs |

Règles appliquées par le rôle `cloud_backend` (`tasks/push_providers.yml`, `templates/cloud-backend-push.env.j2`) :

- clé absente ou vide : variable non posée, **sans erreur** ;
- `fcm_service_account_json` exige `fcm_project_id` ; `apns_key_p8` exige `apns_key_id` et `apns_team_id` ; pas d'apostrophe dans les valeurs ; `apns_env` vaut `production` ou `development` ;
- le `.env` (`/opt/essensys/cloud-backend/.env`) est en `0600`, sa tâche est en `no_log: true` et `diff: false` : aucune valeur dans la sortie ni dans `--diff` ;
- les valeurs sont écrites entre apostrophes dans le `.env` (lues sans interprétation par systemd).

Déploiement : `deploy-portal-stack.yml` (voir [playbooks.md](playbooks.md)), après la migration 022 et le déploiement du cloud. Test hors ligne : `tests/cloud-push-env-render.sh` (clé age jetable, fausses valeurs).

## Créer le projet Firebase (Android, FCM) : étapes pour Nicolas

1. Ouvrir la console Firebase, créer un projet (ou réutiliser celui de l'app Android). Noter son **identifiant de projet** : c'est `fcm_project_id`.
2. Ajouter une application Android avec l'identifiant de package de l'app, télécharger `google-services.json` et le donner à l'équipe de l'app Android (il n'est pas un secret cloud).
3. Paramètres du projet, onglet **Comptes de service** : **Générer une nouvelle clé privée**. Le fichier JSON obtenu est `fcm_service_account_json` ; ne pas le commiter ni le coller dans un ticket.
4. Vérifier que l'API **Firebase Cloud Messaging API (V1)** est activée pour le projet et que le compte de service a le rôle d'envoi de messages (rôle « Administrateur Firebase Cloud Messaging API » ou équivalent).
5. Éditer SOPS : `sops secrets/cloud/essensys.sops.yaml`, ajouter `fcm_project_id` et `fcm_service_account_json` (bloc `|` pour le JSON multi-ligne).
6. Détruire le fichier JSON téléchargé après l'enregistrement dans SOPS.

## Créer la clé APNs (iPhone) : étapes pour Nicolas

1. Dans le compte Apple Developer, **Certificates, Identifiers & Profiles**, **Identifiers** : vérifier que l'App ID de l'app iPhone (`essensys.essensys-iphone`) a la capacité **Push Notifications**.
2. **Keys**, **+** : créer une clé avec le service **Apple Push Notifications service (APNs)**. Télécharger le fichier `AuthKey_<KEYID>.p8` : **Apple ne le propose qu'une seule fois**.
3. Noter l'**identifiant de clé** (10 caractères, aussi dans le nom du fichier) : `apns_key_id`. Noter l'**identifiant d'équipe** (Membership, 10 caractères) : `apns_team_id`.
4. `apns_key_p8` = contenu du fichier `.p8` (lignes `BEGIN`/`END PRIVATE KEY` comprises). `apns_bundle_id` = `essensys.essensys-iphone`. `apns_env` = `production` pour TestFlight et l'App Store ; `development` seulement pour une build installée depuis Xcode.
5. Éditer SOPS : `sops secrets/cloud/essensys.sops.yaml` et ajouter les cinq clés `apns_*`.
6. Détruire le fichier `.p8` téléchargé après l'enregistrement dans SOPS (une clé perdue se révoque et se recrée).

## Vérifier sans afficher de secret

- Contrôle à blanc : `ansible-playbook -i inventory deploy-portal-stack.yml --check --diff` (la tâche du `.env` n'affiche rien).
- Sur le serveur : `sudo grep -c '^FCM_SERVICE_ACCOUNT_JSON=' /opt/essensys/cloud-backend/.env` (compte seulement) et le journal du service : `push_unavailable` absent quand les deux fournisseurs sont configurés.
- Rotation : modifier la valeur dans SOPS puis redéployer ; le backend est redémarré par le handler.
