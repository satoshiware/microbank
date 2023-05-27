#!/bin/bash

echo "This script only works once on a fresh install and cannot be undone automatically!"
echo "If port changes have already been changed, new changes will need to be done manually."
read -p "enter new Bitcoin Core (micro) port: "; MICROPORT="$REPLY"
read -p "enter new RPC (micro) port: "; RPCPORT="$REPLY"
read -p "enter new SSH port: "; SSHPORT="$REPLY"

# Change SSH port in sshd config
sudo sed -i "s/#Port 22/Port ${SSHPORT}/g" /etc/ssh/sshd_config

# Update firewall
sudo ufw delete allow 22/tcp
sudo ufw allow ${SSHPORT}/tcp

# Change Bitcoin Core (micro) port in p2pssh service
sudo sed -i "s/19333/${MICROPORT}/g" /etc/systemd/system/p2pssh@.service

# Add new ports to the Bitcoin (micro) configuration file
sudo sed -i "1s/^/rpcport=${RPCPORT}\n/" /etc/bitcoin.conf
sudo sed -i "1s/^/port=${MICROPORT}\n/" /etc/bitcoin.conf# Remind user to restart the instance

clear; echo "Don't forget to exit to PowerShell and restart this instance: \"wsl -t \$INSTANCE\""
