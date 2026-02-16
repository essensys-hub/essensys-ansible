#!/bin/bash

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MONITOR_SCRIPT="$SCRIPT_DIR/monitor.py"
SERVICE_USER="essensys"
USER_HOME="/home/$SERVICE_USER"

# Couleurs
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== Configuration Automatique du Moniteur Essensys ===${NC}"

# Verifier root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}[ERROR]${NC} Ce script doit etre execute en tant que root (sudo)."
    exit 1
fi

# 1. Rendre le script executable
if [ -f "$MONITOR_SCRIPT" ]; then
    chmod +x "$MONITOR_SCRIPT"
    echo -e "${GREEN}[OK]${NC} Script rendu executable : $MONITOR_SCRIPT"
else
    echo -e "${RED}[ERROR]${NC} Fichier introuvable : $MONITOR_SCRIPT"
    exit 1
fi

# 2. Configurer le demarrage automatique (Autologin) sur tty1
echo -e "\n${GREEN}Configuration de l'autologin sur tty1...${NC}"
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $SERVICE_USER --noclear %I \$TERM
EOF
systemctl daemon-reload
echo -e "${GREEN}[OK]${NC} Autologin configure pour l'utilisateur $SERVICE_USER sur tty1."

# 3. Configurer sudo sans mot de passe pour le script
echo -e "\n${GREEN}Configuration de sudoers...${NC}"
SUDOERS_FILE="/etc/sudoers.d/essensys-monitor"
echo "$SERVICE_USER ALL=(ALL) NOPASSWD: /usr/bin/python3 $MONITOR_SCRIPT" > "$SUDOERS_FILE"
echo "$SERVICE_USER ALL=(ALL) NOPASSWD: /usr/bin/docker" >> "$SUDOERS_FILE"
echo "$SERVICE_USER ALL=(ALL) NOPASSWD: /usr/bin/raspi-config" >> "$SUDOERS_FILE"
echo "$SERVICE_USER ALL=(ALL) NOPASSWD: /usr/bin/reboot" >> "$SUDOERS_FILE"
chmod 440 "$SUDOERS_FILE"
echo -e "${GREEN}[OK]${NC} Permissions sudo configurees dans $SUDOERS_FILE."

# 4. Ajouter le lancement dans .bashrc
echo -e "\n${GREEN}Configuration de .bashrc...${NC}"
BASHRC="$USER_HOME/.bashrc"
MARKER="# ESSENSYS MONITOR AUTOSTART"

if [ -f "$BASHRC" ]; then
    if ! grep -q "$MARKER" "$BASHRC"; then
        cat >> "$BASHRC" <<EOF

$MARKER
# Lancer le moniteur uniquement sur tty1 (ecran physique)
if [ -z "\$SSH_CLIENT" ] && [ -z "\$SSH_TTY" ]; then
    if [ "\$(tty)" = "/dev/tty1" ]; then
        # Attendre un peu que le reseau soit pret
        sleep 5
        sudo /usr/bin/python3 $MONITOR_SCRIPT
    fi
fi
EOF
        echo -e "${GREEN}[OK]${NC} Lancement automatique ajoute a $BASHRC"
        chown "$SERVICE_USER:$SERVICE_USER" "$BASHRC"
    else
        echo -e "${YELLOW}[INFO]${NC} Configuration deja presente dans $BASHRC"
    fi
else
    echo -e "${RED}[ERROR]${NC} Fichier $BASHRC introuvable. L'utilisateur $SERVICE_USER existe-t-il ?"
fi

echo -e "\n${GREEN}=== Configuration terminee ===${NC}"
echo "Le moniteur se lancera automatiquement au prochain redemarrage."
echo "Pour tester maintenant : sudo reboot"
