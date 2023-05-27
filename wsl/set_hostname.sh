#!/bin/bash

# Get the desired hostname from the user
read -p "Enter the desired hostname: "

# Generate WSL configuration
echo "[network]" | sudo tee /etc/wsl.conf
echo "hostname = $REPLY" | sudo tee -a /etc/wsl.conf
echo "generateHosts = false" | sudo tee -a /etc/wsl.conf
echo "[boot]" | sudo tee -a /etc/wsl.conf
echo "systemd=true" | sudo tee -a /etc/wsl.conf

# Update hostname in hosts file
sudo sed -i "s/$(hostname)/${REPLY}/g" /etc/hosts

# Get the default username from the user
read -p "Enter the default username: "
echo "[user]" | sudo tee -a /etc/wsl.conf
echo "default=${REPLY}" | sudo tee -a /etc/wsl.conf

# User Reminder
clear
echo "Don\'t forget to exit to powershell and restart this instance"
echo "wsl --unregister \$INSTANCE"
