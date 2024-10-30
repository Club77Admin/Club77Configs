#!/bin/bash

# Upgrade
sudo apt update
sudo apt dist-upgrade

# Hostname
sudo sed -i 's/^/# /' /etc/hostname
sudo sed -i '1 i\oracle.club77.org' /etc/hostname

# Firewall
sudo apt install ufw
sudo ufw allow OpenSSH
echo "Ready to enable firewall, okay to proceed?"
echo "--- waiting for key press ---"
read -n 1 -s
sudo ufw enable

# Github
ssh-keygen -t ed25519 -C "club77@club77.org" -P -q
echo "Public key generated:"
cat ~/.ssh/id_ed25519.pub
echo "Add public key to github before continuing"
echo "--- waiting for key press ---"
read -n 1 -s
ssh-keyscan github.com >> ~/.ssh/known_hosts
git clone git@github.com:Club77Admin/Club77Configs.git



sudo cp Club77Configs/ufw/Apache /etc/ufw/applications.d/
sudo ufw allow "Apache Full"



sudo cp Club77Configs/ufw/Dovecot /etc/ufw/applications.d/
sudo ufw allow "Dovecot Secure IMAP"



sudo cp Club77Configs/ufw/SMTP /etc/ufw/applications.d/
sudo ufw allow "SMTP"
sudo ufw allow "SMTP Secure"
