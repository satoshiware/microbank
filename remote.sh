#!/bin/bash

# Make sure we are not running as root, but that we have sudo privileges.
if [[ "$(id -u)" = "0" ]]; then
    if ! id "satoshi" >/dev/null 2>&1; then
        adduser --gecos "" satoshi
        sudo usermod -aG sudo satoshi
    fi

    cp $0 /home/satoshi/remote.sh
    sudo -u satoshi bash /home/satoshi/remote.sh
    exit 0

elif [ "$(sudo -l | grep '(ALL : ALL) ALL' | wc -l)" = 0 ]; then
   echo "You do not have enough sudo privileges!"
   exit 1
fi
cd ~; sudo pwd # Print Working Directory; have the user enable sudo access if not already.

# Create .ssh folder and known_hosts file for the root
sudo mkdir -p /root/.ssh
sudo touch /root/.ssh/known_hosts
sudo chmod 700 /root/.ssh
sudo chmod 644 /root/.ssh/known_hosts

# Run latest updates and upgrades
sudo apt-get -y update
sudo apt-get -y upgrade

# Install needed packages
sudo apt-get -y install ufw autossh ssh

# Generate public/private keys (non-encrytped)
sudo ssh-keygen -t ed25519 -f /root/.ssh/p2pkey -N "" -C ""

# Create systemd remote connection Service File
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

# Display this remote mining bridge information
echo ""; echo "Hostname: $(hostname)"
echo "P2P Key (Public): $(sudo cat /root/.ssh/p2pkey.pub)"; echo ""

# Get the necessary details to connect to the Level 3 node
echo "Need to get the details in order to connect this remote mining bridge to your level 3 node..."
read -p "Target's Host (Public) Key: " HOSTKEY
read -p "Target's Address: " TARGETADDRESS
read -p "Target's SSH PORT (default = 22): " SSHPORT; if [ -z $SSHPORT ]; then SSHPORT="22"; fi
read -p "Target's Stratum Port (default = 3333): " STRATUMPORT; if [ -z $STRATUMPORT ]; then STRATUMPORT="3333"; fi

# Update known_hosts
HOSTSIG=$(ssh-keyscan -p ${SSHPORT} -H ${TARGETADDRESS})
if [[ "${HOSTSIG}" == *"${HOSTKEY}"* ]]; then
    sudo sed -i "/ssh-ed25519/d" /root/.ssh/known_hosts 2> /dev/null # Remove prexisting hosts
    echo "${HOSTSIG} # LVL3 Address is ${TARGETADDRESS}:${SSHPORT}" | sudo tee -a /root/.ssh/known_hosts
else
    echo "CRITICAL ERROR: REMOTE HOST IDENTIFICATION DOES NOT MATCH GIVEN HOST KEY!!"
    exit 1
fi

# Create p2pssh@ remote connection environment file and start its corresponding systemd service
cat << EOF | sudo tee /etc/default/p2pssh@remote
LOCAL_PORT=3333
FORWARD_PORT=${STRATUMPORT}
TARGET=${TARGETADDRESS}
TARGET_PORT=${SSHPORT}
EOF

# Reload/Enable System Control for new processes
sudo systemctl daemon-reload
sudo systemctl stop p2pssh@remote
sudo systemctl enable p2pssh@remote --now

# Setup/Enable the Uncomplicated Firewall (UFW)
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh # Open Default SSH Port
sudo ufw --force enable # Enable Firewall @ Boot and Start it now!

# Open firewall to the stratum port for any local ip
sudo ufw allow from 192.168.0.0/16 to any port 3333
sudo ufw allow from 172.16.0.0/12 to any port 3333
sudo ufw allow from 10.0.0.0/8 to any port 3333

echo ""; echo "Mining Address:"; echo "    stratum+tcp://$(hostname -I | tr -d '[:blank:]'):3333"; echo ""