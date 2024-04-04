#!/bin/bash

# Make sure we are not running as root, but that we have sudo privileges.
if [ "$(id -u)" = "0" ]; then
   echo "This script must NOT be run as root (or with sudo)!"
   echo "if you need to create a sudo user (e.g. satoshi), run the following commands:"
   echo "   sudo adduser satoshi"
   echo "   sudo usermod -aG sudo satoshi"
   echo "   sudo su satoshi # Switch to the new user"
   exit 1
elif [ "$(sudo -l | grep '(ALL : ALL) ALL' | wc -l)" = 0 ]; then
   echo "You do not have enough sudo privileges!"
   exit 1
fi
cd ~; sudo pwd # Print Working Directory; have the user enable sudo access if not already.

# Give the user pertinent information about this script and how to use it.
echo "This script installs a p2p micronode (within a cluster) used to manage connections with all other internal and external nodes."
echo "You will need the micronode download URL (tar.gz file) with its SHA 256 Checksum to continue."
echo "To execute this script, login as a sudo user (that is not root) and execute the following commands:"
echo "    sudo apt-get -y install git"
echo "    cd ~; git clone https://github.com/satoshiware/microbank"
echo "    cd microbank/scripts"
echo "    sudo chmod +x micronode_cluster_p2p.sh"
echo "    ./micronode_cluster_p2p.sh"
echo ""
echo "Don't forget to install the connection utility:"
echo "    ./p2pconnect.sh --install "
echo ""
echo "FYI:"
echo "    Use the p2pconnect utility (just type \"p2pconnect\" at the prompt) to create, view, and delete connections."
echo "    The \"$USER/.ssh/authorized_keys\" file contains administrator login keys."
echo "    The \"/var/lib/bitcoin/micro\" directory contains debug logs, blockchain, etc."
read -p "Press the enter key to continue..."

# Create .ssh folder and authorized_keys file if it does not exist
if ! [ -f ~/.ssh/authorized_keys ]; then
    sudo mkdir -p ~/.ssh
    sudo touch ~/.ssh/authorized_keys
    sudo chown -R $USER:$USER ~/.ssh
    sudo chmod 700 ~/.ssh
    sudo chmod 600 ~/.ssh/authorized_keys
fi

# Run latest updates and upgrades
sudo apt-get -y update
sudo DEBIAN_FRONTEND=noninteractive apt-get -y install --only-upgrade openssh-server # Upgrade seperatly to ensure non-interactive mode
sudo apt-get -y upgrade

# Install Packages
sudo apt-get -y install wget psmisc autossh ssh ufw python3 jq

# Download Bitcoin Core (micro), Verify Checksum
read -p "Bitcoin Core URL (.tar.gz) source (/w compiled microcurrency): " SOURCE
read -p "SHA 256 Checksum for the .tar.gz source file: " CHECKSUM

wget $SOURCE
if ! [ -f ~/${SOURCE##*/} ]; then echo "Error: Could not download source!"; exit 1; fi
if [[ ! "$(sha256sum ~/${SOURCE##*/})" == *"$CHECKSUM"* ]]; then
    echo "Error: SHA 256 Checksum for file \"~/${SOURCE##*/}\" was not what was expected!"
    exit 1
fi
tar -xzf $SOURCE
rm $SOURCE

# Install Binaries
sudo install -m 0755 -o root -g root -t /usr/bin bitcoin-install/bin/*
rm -rf bitcoin-install

# Prepare Service Configuration
cat << EOF | sudo tee /etc/systemd/system/bitcoind.service
[Unit]
Description=Bitcoin daemon
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/bin/bitcoind -micro -daemonwait -pid=/run/bitcoin/bitcoind.pid -conf=/etc/bitcoin.conf -datadir=/var/lib/bitcoin
ExecStop=/usr/bin/bitcoin-cli -micro -conf=/etc/bitcoin.conf -datadir=/var/lib/bitcoin stop

Type=forking
PIDFile=/run/bitcoin/bitcoind.pid
Restart=always
RestartSec=30
TimeoutStartSec=infinity
TimeoutStopSec=600

### Run as bitcoin:bitcoin ###
User=bitcoin
Group=bitcoin

### /run/bitcoin ###
RuntimeDirectory=bitcoin
RuntimeDirectoryMode=0710

### /var/lib/bitcoin ###
StateDirectory=bitcoin
StateDirectoryMode=0710

### Hardening measures ###
PrivateTmp=true
ProtectSystem=full
ProtectHome=true
NoNewPrivileges=true
PrivateDevices=true
MemoryDenyWriteExecute=true

[Install]
WantedBy=multi-user.target
EOF

#Create a bitcoin System User
sudo useradd --system --shell=/sbin/nologin bitcoin

# Wrap the Bitcoin CLI Binary with its Runtime Configuration
echo "alias btc=\"sudo -u bitcoin /usr/bin/bitcoin-cli -micro -datadir=/var/lib/bitcoin -conf=/etc/bitcoin.conf\"" | sudo tee -a /etc/bash.bashrc # Reestablish alias @ boot

# Generate Bitcoin Configuration File with the Appropriate Permissions
cat << EOF | sudo tee /etc/bitcoin.conf
[micro]
EOF
sudo chown root:bitcoin /etc/bitcoin.conf
sudo chmod 640 /etc/bitcoin.conf

# Configure bitcoind's Log Files; Prevents them from Filling up the Partition
cat << EOF | sudo tee /etc/logrotate.d/bitcoin
/var/lib/bitcoin/micro/debug.log {
$(printf '\t')create 660 root bitcoin
$(printf '\t')daily
$(printf '\t')rotate 14
$(printf '\t')compress
$(printf '\t')delaycompress
$(printf '\t')sharedscripts
$(printf '\t')postrotate
$(printf '\t')$(printf '\t')killall -HUP bitcoind
$(printf '\t')endscript
}
EOF

# Setup a Symbolic Link to Standardize the Location of bitcoind's Log Files
sudo mkdir -p /var/log/bitcoin/micro
sudo ln -s /var/lib/bitcoin/micro/debug.log /var/log/bitcoin/micro/debug.log
sudo chown root:bitcoin -R /var/log/bitcoin
sudo chmod 660 -R /var/log/bitcoin

# Install/Setup/Enable the Uncomplicated Firewall (UFW)
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh # Open Default SSH Port
sudo ufw --force enable # Enable Firewall @ Boot and Start it now!

# Install/Setup/Enable SSH(D)
sudo sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config # Disable password login
sudo sed -i 's/X11Forwarding yes/#X11Forwarding no/g' /etc/ssh/sshd_config # Disable X11Forwarding (default value)
sudo sed -i 's/#AllowTcpForwarding yes/AllowTcpForwarding Local/g' /etc/ssh/sshd_config # Only allow local port forwarding
sudo sed -i 's/#.*StrictHostKeyChecking ask/\ \ \ \ StrictHostKeyChecking yes/g' /etc/ssh/ssh_config # Enable strict host verification

echo -e "\nMatch User *,"'!'"p2p,"'!'"root,"'!'"$USER" | sudo tee -a /etc/ssh/sshd_config
echo -e "\tAllowTCPForwarding no" | sudo tee -a /etc/ssh/sshd_config
echo -e "\tPermitTTY no" | sudo tee -a /etc/ssh/sshd_config
echo -e "\tForceCommand /usr/sbin/nologin" | sudo tee -a /etc/ssh/sshd_config

echo -e "\nMatch User p2p" | sudo tee -a /etc/ssh/sshd_config
echo -e "\tPermitTTY no" | sudo tee -a /etc/ssh/sshd_config
echo -e "\tPermitOpen localhost:19333" | sudo tee -a /etc/ssh/sshd_config # Denies any request of local forwarding besides localhost:19333

# Setup a "no login" user called "p2p"
sudo useradd -s /bin/false -m -d /home/p2p p2p

# Create (p2p) .ssh folder; Set ownership and permissions
sudo mkdir -p /home/p2p/.ssh
sudo touch /home/p2p/.ssh/authorized_keys
sudo chown -R p2p:p2p /home/p2p/.ssh
sudo chmod 700 /home/p2p/.ssh
sudo chmod 600 /home/p2p/.ssh/authorized_keys

# Generate public/private keys (non-encrytped)
sudo ssh-keygen -t ed25519 -f /root/.ssh/p2pkey -N "" -C ""

# Create known_hosts file
sudo touch /root/.ssh/known_hosts

# Create systemd Service File
cat << EOF | sudo tee /etc/systemd/system/p2pssh@.service
[Unit]
Description=AutoSSH %I Tunnel Service
Before=bitcoind.service
After=network-online.target

[Service]
Environment="AUTOSSH_GATETIME=0"
EnvironmentFile=/etc/default/p2pssh@%i
ExecStart=/usr/bin/autossh -M 0 -NT -o ServerAliveInterval=30 -o ExitOnForwardFailure=yes -o "ServerAliveCountMax 3" -i /root/.ssh/p2pkey -L \${LOCAL_PORT}:localhost:\${FORWARD_PORT} -p \${TARGET_PORT} p2p@\${TARGET}

RestartSec=5
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Reload/Enable System Control for new processes
sudo systemctl daemon-reload
sudo systemctl enable ssh
sudo systemctl enable bitcoind

# Install the micronode connect utility (mnconnect.sh)
bash ~/microbank/scripts/p2pconnect.sh -i

# Restart the machine
sudo reboot now