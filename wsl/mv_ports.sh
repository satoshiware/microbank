#!/bin/bash

echo "This script only works once on a fresh install and cannot be undone automatically!"
echo "If port changes have already been changed, new changes will need to be done manually."
read -p "Enter new Bitcoin Core (micro) port: "; MICROPORT="$REPLY"
read -p "Enter new RPC (micro) port: "; RPCPORT="$REPLY"
read -p "Enter new Stratum port: "; STRATPORT="$REPLY"
read -p "Enter new SSH port: "; SSHPORT="$REPLY"

# Change SSH port in sshd config
sudo sed -i "s/#Port 22/Port ${SSHPORT}/g" /etc/ssh/sshd_config

# Update firewall
sudo ufw delete allow 22/tcp
sudo ufw allow ${SSHPORT}/tcp

# Change Bitcoin Core (micro) port in sshd_config
sudo sed -i "s/19333/${MICROPORT}/g" /etc/ssh/sshd_config

# Change RPC Bitcoin Core (micro) port in and ckproxy.conf
sudo sed -i "s/19332/${RPCPORT}/g" /etc/ckproxy.conf
sudo sed -i "s/19332/${RPCPORT}/g" /etc/ckpool.conf

# Add new ports to the Bitcoin (micro) configuration file
echo "port=${MICROPORT}" | sudo tee -a /etc/bitcoin.conf
echo "rpcport=${RPCPORT}" | sudo tee -a /etc/bitcoin.conf

# Change Stratum port in and ckproxy/ckpool.conf, sshd_config, and p2pssh@stratum environment file
sudo sed -i "s/3333/${STRATPORT}/g" /etc/ckproxy.conf
sudo sed -i "s/3333/${STRATPORT}/g" /etc/ckpool.conf
sudo sed -i "s/3333/${STRATPORT}/g" /etc/ssh/sshd_config
sudo sed -i "s/3333/${STRATPORT}/g" /etc/default/p2pssh@stratum

# Remind user to restart the instance
clear; echo "Don't forget to exit to PowerShell and restart this instance: \"wsl -t \$INSTANCE\""
