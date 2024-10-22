#!/bin/bash

# Make sure we are not running as root, but that we have sudo privileges.
if [ "$(id -u)" = "0" ]; then
   echo "This script must NOT be run as root (or with sudo)!"
   exit 1
elif [ "$(sudo -l | grep '(ALL : ALL) ALL' | wc -l)" = 0 ]; then
   echo "You do not have enough sudo privileges!"
   exit 1
fi
cd ~; sudo pwd # Print Working Directory; have the user enable sudo access if not already.

# Give the user pertinent information about this script and how to use it.
cat << EOF | sudo tee ~/readme.txt
This readme was generated by the "bitcoin_wallet_node.sh" install script.

Use this node to manage the following wallets:
    The "satoshi_coins" wallet used to load Satoshi Coins
    The "mining" wallet used to receive proceeds from mining
    The "bank" wallet is a general use wallet for everything else
The /usr/local/sbin/wallu script facilitates many of the desired wallet activities.
Also installed is a script, /usr/local/sbin/send_email, to send email reports to the admins.

Note: This is a pruned bitcoin node. The rescan feature is not possible on a pruned blockchain; therefore,
    importing private keys or addresses to watch is not possible. Also, wallet files cannot be imported either
    without downloading the entire blockchain once again.

FYI:
    The "/var/lib/bitcoin" directory contains debug logs, blockchain, etc.
    The bitcoind's log files can be view with this file: "/var/log/bitcoin/debug.log" (links to /var/lib/bitcoin/debug.log)
    Bitcoin configuratijon: /etc/bitcoin.conf
    The "sudo systemctl status bitcoind" command show the status of the bitcoin daemon.
EOF
read -p "Press the enter key to continue..."

# Run latest updates and upgrades
sudo apt-get -y update
sudo DEBIAN_FRONTEND=noninteractive apt-get -y install --only-upgrade openssh-server # Upgrade seperatly to ensure non-interactive mode
sudo apt-get -y upgrade

# Install Packages
sudo apt-get -y install wget ufw jq

# Load global environment variables
source ~/globals.env

# Download Bitcoin Core, Verify Checksum
wget $BTC_CORE_SOURCE
if ! [ -f ~/${BTC_CORE_SOURCE##*/} ]; then echo "Error: Could not download source!"; exit 1; fi
if [[ ! "$(sha256sum ~/${BTC_CORE_SOURCE##*/})" == *"$BTC_CORE_CHECKSUM"* ]]; then
    echo "Error: SHA 256 Checksum for file \"~/${BTC_CORE_SOURCE##*/}\" was not what was expected!"
    exit 1
fi
tar -xzf ${BTC_CORE_SOURCE##*/}
rm ${BTC_CORE_SOURCE##*/}

# Install Binaries
sudo install -m 0755 -o root -g root -t /usr/bin bitcoin-*/bin/*
rm -rf bitcoin-*

# Prepare Service Configuration
cat << EOF | sudo tee /etc/systemd/system/bitcoind.service
[Unit]
Description=Bitcoin daemon
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/bin/bitcoind -daemonwait -pid=/run/bitcoin/bitcoind.pid -conf=/etc/bitcoin.conf -datadir=/var/lib/bitcoin
ExecStop=/usr/bin/bitcoin-cli -conf=/etc/bitcoin.conf -datadir=/var/lib/bitcoin stop

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

# Create a bitcoin System User
sudo useradd --system --shell=/sbin/nologin bitcoin

# Wrap the Bitcoin CLI Binary with its Runtime Configuration
echo "alias btc=\"sudo -u bitcoin /usr/bin/bitcoin-cli -datadir=/var/lib/bitcoin -conf=/etc/bitcoin.conf\"" | sudo tee -a /etc/bash.bashrc # Reestablish alias @ boot

# Generate Bitcoin Configuration File with the Appropriate Permissions
cat << EOF | sudo tee /etc/bitcoin.conf
# [core]
# Only downloads and relays blocks; ignores unconfirmed transaction and disables most of the mempool functionality (i.e. maxmempool=0).
blocksonly=1
# Set database cache size in MB (The minimum value is 4; default is 450).
dbcache=256
# Reduce storage requirements by only storing this many MBs of the most recent blocks (The minimum value is 550).
prune=550

# [network]
# Connect only to the specified node and nothing else.
connect=$BTC_NODE_IP
# Accept incoming connections from peers.
listen=0

# [wallet]
# Bech32
addresstype=bech32
# Bech32
changetype=bech32
EOF
sudo chown root:bitcoin /etc/bitcoin.conf
sudo chmod 640 /etc/bitcoin.conf

# Configure bitcoind's Log Files; Prevents them from Filling up the Partition
cat << EOF | sudo tee /etc/logrotate.d/bitcoin
/var/log/bitcoin/debug.log {
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
sudo mkdir -p /var/log/bitcoin
sudo ln -s /var/lib/bitcoin/debug.log /var/log/bitcoin/debug.log
sudo chown root:bitcoin -R /var/log/bitcoin
sudo chmod 660 -R /var/log/bitcoin

# Install/Setup/Enable the Uncomplicated Firewall (UFW)
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh # Open Default SSH Port
sudo ufw --force enable # Enable Firewall @ Boot and Start it now!

# Generating Strong Wallet Passphrase
STRONGPASSPF=$(openssl rand -base64 24)
STRONGPASSPF=${STRONGPASSPF//\//0} # Replace '/' characters with '0'
STRONGPASSPF=${STRONGPASSPF//+/1} # Replace '+' characters with '1'
STRONGPASSPF=${STRONGPASSPF//=/} # Replace '=' characters with ''
STRONGPASSPF=${STRONGPASSPF//O/0} # Replace 'O' (o) characters with '0'
STRONGPASSPF=${STRONGPASSPF//l/1} # Replace 'l' (L) characters with '1'
echo $STRONGPASSPF | sudo tee /root/passphrase
sudo chmod 400 /root/passphrase

# Reload/Enable System Control for new processes
sudo systemctl daemon-reload
sudo systemctl enable bitcoind --now
echo "waiting a few seconds for bitcoind to start"; sleep 15

# Generate Wallets
sudo -u bitcoin /usr/bin/bitcoin-cli -datadir=/var/lib/bitcoin -conf=/etc/bitcoin.conf --named createwallet wallet_name="satoshi_coins" passphrase=$(sudo cat /root/passphrase) load_on_startup=true
sudo -u bitcoin /usr/bin/bitcoin-cli -datadir=/var/lib/bitcoin -conf=/etc/bitcoin.conf --named createwallet wallet_name="mining" passphrase=$(sudo cat /root/passphrase) load_on_startup=true
sudo -u bitcoin /usr/bin/bitcoin-cli -datadir=/var/lib/bitcoin -conf=/etc/bitcoin.conf --named createwallet wallet_name="bank" passphrase=$(sudo cat /root/passphrase) load_on_startup=true

# Install the Bitcoin Wallet utility and email utility
bash ~/microbank/scripts/wallu.sh --install
bash ~/microbank/scripts/send_messages.sh --install

# Create links (for backup purposes) to all critical files needed to restore this node
cd ~; mkdir backup
sudo ln -s /var/lib/bitcoin/satoshi_coins ~/backup
sudo ln -s /var/lib/bitcoin/mining ~/backup
sudo ln -s /var/lib/bitcoin/bank ~/backup
sudo ln -s /root/passphrase ~/backup
sudo ln -s /etc/default/send_messages.env ~/backup

# If "~/restore" folder is present then restore all pertinent files; assumes all files are present
if [[ -d ~/restore ]]; then
    # Restore ownership to files
    sudo chown -R bitcoin:bitcoin ~/restore/satoshi_coins
    sudo chown -R bitcoin:bitcoin ~/restore/mining
    sudo chown -R bitcoin:bitcoin ~/restore/bank
    sudo chown root:root ~/restore/passphrase
    sudo chown root:root ~/restore/send_messages.env

    # Move files to their correct locations
    sudo systemctl stop bitcoind; echo "Waiting 30 seconds for bitcoind to shutdown..."; sleep 30
    sudo rm -rf /var/lib/bitcoin/satoshi_coins
    sudo rm -rf /var/lib/bitcoin/mining
    sudo rm -rf /var/lib/bitcoin/bank
    sudo mv -f ~/restore/satoshi_coins /var/lib/bitcoin
    sudo mv -f ~/restore/mining /var/lib/bitcoin
    sudo mv -f ~/restore/bank /var/lib/bitcoin
    sudo mv ~/restore/passphrase /root/passphrase
    sudo mv ~/restore/send_messages.env /etc/default/send_messages.env

    # Remove the "~/restore" folder
    cd ~; sudo rm -rf restore
fi

# Restart the machine
sudo reboot now