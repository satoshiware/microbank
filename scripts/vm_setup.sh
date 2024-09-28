#!/bin/bash

# Disable password for satoshi
echo "satoshi ALL=(ALL) NOPASSWD: ALL" | EDITOR='tee -a' visudo

#### Update and Upgrade
apt-get -y update
apt-get -y upgrade

#### Install Packages
apt-get -y install watchdog
apt-get -y install tuned # A system tuning service for Linux.
apt-get -y install curl

#### Install vmctl VM control script
echo "PATH=\"/usr/local/sbin:\$PATH\"" | tee -a ~/.profile

#### Disable Password Authentication & configure Yubikey & Host Public Key Access
sed -i 's/#.*PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config # Disable password login
mkdir -p ~/.ssh
touch ~/.ssh/authorized_keys
chown -R $USER:$USER ~/.ssh
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys
#read -p "Yubikey Public Key: " YUBIKEY; echo $YUBIKEY | tee -a ~/.ssh/authorized_keys; echo "Yubikey added to ~/.ssh/authorized_keys"
#read -p "Base Host Server Public Key: " HOSTKEY; echo "$HOSTKEY # Base Host Server Key" | tee -a ~/.ssh/authorized_keys; echo "Base Host Server Key added to ~/.ssh/authorized_keys"

#### Tune the machine for running KVM guests
systemctl enable tuned --now; sleep 5 # Enable and start the TuneD service and wait 5 seconds
tuned-adm profile virtual-guest # This optimizes the host for running KVM guests

#### Configure Watchdog
cat << EOF | tee /etc/watchdog.conf
watchdog-device = /dev/watchdog
log-dir =  /var/log/watchdog
realtime = yes
priority = 1
EOF
sed -i 's/watchdog_module="none"/watchdog_module="i6300esb"/g' /etc/default/watchdog # Set the watchdog_module to i6300esb
systemctl enable watchdog # Enable WDT to start on next boot
echo ""; echo "Notes: Run \"dmesg | grep i6300\" to check the watchdog module is up and working"
echo "       Run \"echo c > /proc/sysrq-trigger\" as root to verify the wdt will reset the machine"; echo ""

echo "Fully powering off the VM (not restart). This is important as it'll allow it to adopt the new [WDT] hardware configuration."
shutdown now