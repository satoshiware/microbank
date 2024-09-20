#!/bin/bash

#### Make sure we are not running as root, but that we have sudo privileges.
if [ "$(id -u)" = "0" ]; then
   echo "This script must NOT be run as root (or with sudo)!"
   exit 1
elif [ "$(sudo -l | grep '(ALL : ALL) ALL' | wc -l)" = 0 ]; then
   echo "You do not have enough sudo privileges!"
   exit 1
fi
cd ~; echo satoshi | sudo -S pwd # Enable sudo access if not already.

# Disable sudo password for satoshi
echo "satoshi ALL=(ALL) NOPASSWD: ALL" | sudo EDITOR='tee -a' visudo

#### Update and Upgrade
sudo apt-get -y update
sudo apt-get -y upgrade

#### Install Packages
sudo apt-get -y install watchdog
sudo apt-get -y install tuned # A system tuning service for Linux.
sudo apt-get -y install curl

#### Install vmctl VM control script
echo "PATH=\"/usr/local/sbin:\$PATH\"" | sudo tee -a ~/.profile

#### Disable Password Authentication & configure Yubikey & Host Public Key Access
sudo sed -i 's/#.*PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config # Disable password login
sudo mkdir -p ~/.ssh
sudo touch ~/.ssh/authorized_keys
sudo chown -R $USER:$USER ~/.ssh
sudo chmod 700 ~/.ssh
sudo chmod 600 ~/.ssh/authorized_keys
read -p "Yubikey Public Key: " YUBIKEY; echo $YUBIKEY | sudo tee -a ~/.ssh/authorized_keys; echo "Yubikey added to ~/.ssh/authorized_keys"
read -p "Base Host Server Public Key: " HOSTKEY; echo "$HOSTKEY # Base Host Server Key" | sudo tee -a ~/.ssh/authorized_keys; echo "Base Host Server Key added to ~/.ssh/authorized_keys"

#### Tune the machine for running KVM guests
sudo systemctl enable tuned --now; sleep 5 # Enable and start the TuneD service and wait 5 seconds
sudo tuned-adm profile virtual-guest # This optimizes the host for running KVM guests

#### Configure Watchdog
cat << EOF | sudo tee /etc/watchdog.conf
watchdog-device = /dev/watchdog
log-dir =  /var/log/watchdog
realtime = yes
priority = 1
EOF
sudo sed -i 's/watchdog_module="none"/watchdog_module="i6300esb"/g' /etc/default/watchdog # Set the watchdog_module to i6300esb
sudo systemctl enable watchdog # Enable WDT to start on next boot
echo ""; echo "Notes: Run \"sudo dmesg | grep i6300\" to check the watchdog module is up and working"
echo "       Run \"echo c > /proc/sysrq-trigger\" as root to verify the wdt will reset the machine"; echo ""

echo "Fully powering off the VM (not restart). This is important as it'll allow it to adopt the new [WDT] hardware configuration."
sudo shutdown now