#!/bin/bash

# Generate WSL configuration and update the hostname
read -p "Enter the desired hostname: "
echo "[network]" | sudo tee /etc/wsl.conf
echo "hostname = $REPLY" | sudo tee -a /etc/wsl.conf
echo "generateHosts = false" | sudo tee -a /etc/wsl.conf
echo "[boot]" | sudo tee -a /etc/wsl.conf
echo "systemd=true" | sudo tee -a /etc/wsl.conf
echo "[user]" | sudo tee -a /etc/wsl.conf
echo "default=$USER" | sudo tee -a /etc/wsl.conf

# Update hostname in hosts file
sudo sed -i "s/$(hostname)/${REPLY}/g" /etc/hosts
