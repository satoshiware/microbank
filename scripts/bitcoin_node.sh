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
This readme was generated by the "bitcoin_node.sh" install script.
A bitcoin node has been installed and readied to receive connections from external services.

FYI:
    The "/var/lib/bitcoin" directory contains debug logs, blockchain, etc.
    The bitcoind's log files can be view with this file: "/var/log/bitcoin/debug.log" (links to /var/lib/bitcoin/debug.log)
    Bitcoin configuratijon: /etc/bitcoin.conf
    The "sudo systemctl status bitcoind" command show the status of the bitcoin daemon.

    JSON RPC & REST API connections on port 8332 are allowed from any local IP.
    JSON RPC Password for user satoshi is "satoshi"

    Also, ZeroMQ (ZMQ) connection access on port 29000 is allowed from any local IP.

Management:
    Make permanent P2P outbound connection:
        btc addnode \$ADDRESS:\$PORT "add"
            ":\$PORT" is not necessary for the default port 8333
        echo -e "# \$NAME, \${DESCRIPTION}\naddnode=\$ADDRESS:\$PORT" | sudo tee -a /etc/bitcoin.conf
            ":\$PORT" is not necessary for the default port 8333
            "\$NAME" and "\${DESCRIPTION}" add desired info' as part of the connections' comment heading
EOF
read -p "Press the enter key to continue..."

# Run latest updates and upgrades
sudo apt-get -y update
sudo DEBIAN_FRONTEND=noninteractive apt-get -y install --only-upgrade openssh-server # Upgrade seperatly to ensure non-interactive mode
sudo apt-get -y upgrade

# Install Packages
sudo apt-get -y install wget ufw

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
# Maintain coinstats index used by the gettxoutsetinfo RPC.
coinstatsindex=1
# Maintain a full transaction index, used by the getrawtransaction rpc call.
txindex=1
# The UTXO database cache size in MB (default 450)
dbcache=1024

# [rpc]
# Accept command line and JSON-RPC commands.
server=1
# Accept public REST requests (runs on same port as JSON-RPC).
rest=1
# Bind to given address to listen for JSON-RPC connections. This option is ignored unless -rpcallowip is also passed. This option can be specified multiple times. (default: 127.0.0.1 and ::1)
rpcbind=0.0.0.0
# Allow JSON-RPC connections from specified source.
rpcallowip=$(hostname -I | cut -d "." -f 1,2,3).0/24

# Set the number of threads to service RPC calls (default = 4)
rpcthreads=16
# Set the depth of the work queue to service RPC calls (default = 16)
rpcworkqueue=32
# Number of seconds after which an uncompleted RPC call will time out (default = 30)
rpcservertimeout=60

# Username (satoshi) and hashed password (satoshi) for JSON-RPC connections. RPC clients connect using rpcuser=<USERNAME>/rpcpassword=<PASSWORD> arguments.
rpcauth=satoshi:170f4d25565cfe8cbd3ab1c81ad25610\$a8327a4d2241c121e0cd88d1b693cdc6aa3dfbcebb6b863545d090f5d7fa614b
# Allow users to access any RPC unless they are listed in an rpcwhitelist entry
rpcwhitelistdefault=0
# Set a whitelist to filter incoming RPC calls for satoshi
rpcwhitelist=satoshi:getbestblockhash,getblock,getblockchaininfo,getblockcount,getblockfilter,getblockhash,getblockheader,getblockstats,getchaintips,getchaintxstats,getdifficulty,getmempoolancestors,getmempooldescendants,getmempoolentry,getmempoolinfo,getrawmempool,gettxout,gettxoutproof,gettxoutsetinfo,verifytxoutproof,getmemoryinfo,getrpcinfo,help,uptime,getblocktemplate,getmininginfo,getnetworkhashps,getaddednodeinfo,getconnectioncount,getnettotals,getnetworkinfo,getnodeaddresses,getpeerinfo,listbanned,combinerawtransaction,createrawtransaction,decoderawtransaction,decodescript,getrawtransaction,sendrawtransaction,signrawtransactionwithkey,testmempoolaccept,createmultisig,deriveaddresses,estimatesmartfee,getdescriptorinfo,signmessagewithprivkey,validateaddress,verifymessage,submitblock,submitheader,getindexinfo

# [wallet]
# Do not load the wallet and disable wallet RPC calls.
disablewallet=1

# [zeromq]
# Enable publishing of block hashes
zmqpubhashblock=tcp://localhost:29000
# Enable publishing of transaction hashes
zmqpubhashtx=tcp://localhost:29000
# Enable publishing of raw block hex
zmqpubrawblock=tcp://localhost:29000
# Enable publishing of raw transaction hex
zmqpubrawtx=tcp://localhost:29000
# Enable publish hash block and tx sequence
zmqpubsequence=tcp://localhost:29000

# [network]
# Whitelist P2P peers connecting from the given IP addresses
whitelist=$(hostname -I | cut -d "." -f 1,2,3).0/24
# Add a node IP address "addnode=\$ADDRESS" to connect to and to keep the connection open.
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
sudo ufw allow 8333 # Open P2P node connections on port 8333
sudo ufw allow from $(hostname -I | cut -d "." -f 1,2,3).0/24 to any port 8332 # Open JSON RPC connections on port 8332 from the local network only
sudo ufw allow from $(hostname -I | cut -d "." -f 1,2,3).0/24 to any port 29000 # Open ZeroMQ (ZMQ) connection access on port 29000 from the local network only
sudo ufw --force enable # Enable Firewall @ Boot and Start it now!

# Reload/Enable System Control for new processes
sudo systemctl daemon-reload
sudo systemctl enable bitcoind

# Create links (for backup purposes) to all critical files needed to restore this node
cd ~; mkdir backup
sudo ln -s /etc/bitcoin.conf ~/backup

# If "~/restore" folder is present then restore all pertinent files; assumes all files are present
if [[ -d ~/restore ]]; then
    # Restore ownership to files
    sudo chown root:bitcoin ~/restore/bitcoin.conf

    # Move files to their correct locations
    sudo mv ~/restore/bitcoin.conf /etc/bitcoin.conf

    # Remove the "~/restore" folder
    cd ~; sudo rm -rf restore
fi

# Restart the machine
sudo reboot now