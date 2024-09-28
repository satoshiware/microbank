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
echo "PATH=\"/usr/local/sbin:\$PATH\"" | tee -a /home/satoshi/.profile

#### Disable Password Authentication & configure Yubikey & Host Public Key Access
sed -i 's/#.*PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config # Disable password login
mkdir -p /home/satoshi/.ssh
touch /home/satoshi/.ssh/authorized_keys
chown -R satoshi:satoshi /home/satoshi/.ssh
chmod 700 /home/satoshi/.ssh
chmod 600 /home/satoshi/.ssh/authorized_keys
echo "${1} # Base Host Server Key" | tee -a /home/satoshi/.ssh/authorized_keys # Add Base Host Server Key to /home/satoshi/.ssh/authorized_keys

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
# Note: Run "dmesg | grep i6300" to check the watchdog module is up and working
# Note: Run "echo c > /proc/sysrq-trigger" as root to verify the wdt will reset the machine

#### Fully powering off the VM (not restart). This is important as it'll allow it to adopt the new [WDT] hardware configuration.
shutdown now