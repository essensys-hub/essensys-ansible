#!/bin/bash

# Script pour generer le fichier htpasswd pour l'authentification Traefik
# Usage: ./generate-htpasswd-essensys.sh [username]

set -e

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Verifier que htpasswd est installe
if ! command -v htpasswd &> /dev/null; then
    log_error "htpasswd n'est pas installe. Installation..."
    if [ "$EUID" -ne 0 ]; then 
        log_error "Ce script doit etre execute en tant que root pour installer htpasswd"
        exit 1
    fi
    apt-get update
    apt-get install -y apache2-utils
fi

# Demander le nom d'utilisateur
if [ -z "$1" ]; then
    if [ -r /dev/tty ]; then
        read -r -p "Nom d'utilisateur: " USERNAME < /dev/tty
    else
        log_error "Aucun TTY disponible pour saisir le nom d'utilisateur"
        exit 1
    fi
else
    USERNAME="$1"
fi

if [ -z "$USERNAME" ]; then
    log_error "Le nom d'utilisateur ne peut pas etre vide"
    exit 1
fi

# Fichier de sortie (chemin coherent avec le montage Docker Compose)
HTPASSWD_FILE="/opt/data/config/traefik/users.htpasswd"

# Creer le repertoire si necessaire
mkdir -p "$(dirname "$HTPASSWD_FILE")"

# Demander le mot de passe (sans l'afficher)
if [ -r /dev/tty ]; then
    read -r -s -p "Mot de passe: " PASSWORD < /dev/tty
    echo ""
else
    log_error "Aucun TTY disponible pour saisir le mot de passe"
    exit 1
fi

if [ -z "$PASSWORD" ]; then
    log_error "Le mot de passe ne peut pas etre vide"
    exit 1
fi

# Generer le fichier htpasswd (ecrase l'existant avec le nouvel utilisateur)
log_info "Generation du fichier htpasswd..."
htpasswd -nbB "$USERNAME" "$PASSWORD" > "$HTPASSWD_FILE"

# Definir les permissions
chmod 600 "$HTPASSWD_FILE"

log_info "Fichier htpasswd mis a jour: $HTPASSWD_FILE"
log_info "Utilisateur: $USERNAME"
log_info ""
log_info "Traefik recharge automatiquement le fichier (watch: true)"
log_info "Pour ajouter d'autres utilisateurs, executez a nouveau ce script"
