#!/bin/bash

##### Make sure we are not running as root, but that we have sudo privileges. #####
if [ "$(id -u)" = "0" ]; then
   echo "This script must NOT be run as root (or with sudo)!"
   exit 1
elif [ "$(sudo -l | grep '(ALL : ALL) ALL' | wc -l)" = 0 ]; then
   echo "You do not have enough sudo privileges!"
   exit 1
fi
cd ~; sudo pwd # Print Working Directory; have the user enable sudo access if not already.

##### Give the user pertinent information about this script and how to use it. ##### <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
cat << EOF | sudo tee ~/readme.txt
This readme was generated by the "btcpay.sh" install script.


EOF
read -p "Press the enter key to continue..."

##### Add Microsoft package repository #####
sudo apt-get -y install wget
wget https://packages.microsoft.com/config/ubuntu/20.04/packages-microsoft-prod.deb -O packages-microsoft-prod.deb
sudo dpkg -i packages-microsoft-prod.deb
rm packages-microsoft-prod.deb

##### Run latest updates and upgrades #####
sudo apt-get -y update
sudo DEBIAN_FRONTEND=noninteractive apt-get -y install --only-upgrade openssh-server # Upgrade seperatly to ensure non-interactive mode
sudo apt-get -y upgrade

##### Install Packages #####
sudo apt-get -y install psmisc ufw jq apt-transport-https dotnet-sdk-8.0 nginx postgresql postgresql-contrib xz-utils libpq5
sudo dotnet workload update # Updates all installed dotnet workloads to the newest available versions

# Install Pythong Modules
sudo apt-get -y install python3-pip python3-websockets python3-cryptography python3-gevent python3-gunicorn python3-flask python3-json5
sudo pip install pyln-client flask_restx flask_cors flask_socketio --break-system-packages

##### Install/Setup/Enable the Uncomplicated Firewall (UFW) #####
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh # Open Default SSH Port
sudo ufw allow http # Open Default HTTP Port
sudo ufw allow from $(hostname -I | cut -d "." -f 1,2,3).0/24 to any port 9735 # Open Default lightningd Port for local network only
sudo ufw --force enable # Enable Firewall @ Boot and Start it now!

##### Configure Nginx #####
cat << EOF | sudo tee /etc/nginx/conf.d/default.conf
# If we receive X-Forwarded-Proto, pass it through; otherwise, pass along the scheme used to connect to this server
map \$http_x_forwarded_proto \$proxy_x_forwarded_proto {
    default \$http_x_forwarded_proto;
    ''      \$scheme;
}

# If we receive X-Forwarded-Port, pass it through; otherwise, pass along the server port the client connected to
map \$http_x_forwarded_port \$proxy_x_forwarded_port {
    default \$http_x_forwarded_port;
    ''      \$server_port;
}

# If we receive Upgrade, set Connection to "upgrade"; otherwise, delete any connection header that may have been passed to this server
map \$http_upgrade \$proxy_connection {
    default upgrade;
    '' close;
}

# Set appropriate X-Forwarded-Ssl header
map \$scheme \$proxy_x_forwarded_ssl {
    default off;
    https on;
}

# Apply fix for very long server names
server_names_hash_bucket_size 128;

# Prevent Nginx Information Disclosure
server_tokens off;

gzip_types text/plain text/css application/javascript application/json application/x-javascript text/xml application/xml application/xml+rss text/javascript;
log_format vhost '\$host \$remote_addr - \$remote_user [\$time_local] ' '"\$request" \$status \$body_bytes_sent ' '"\$http_referer" "\$http_user_agent"';
access_log off;

# HTTP 1.1 support
proxy_http_version 1.1;
proxy_buffering off;
proxy_set_header Host \$http_host;
proxy_set_header Upgrade \$http_upgrade;
proxy_set_header Connection \$proxy_connection;
proxy_set_header X-Real-IP \$remote_addr;
proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto \$proxy_x_forwarded_proto;
proxy_set_header X-Forwarded-Ssl \$proxy_x_forwarded_ssl;
proxy_set_header X-Forwarded-Port \$proxy_x_forwarded_port;
proxy_buffer_size 128k;
proxy_buffers 4 256k;
proxy_busy_buffers_size 256k;
client_header_buffer_size 500k;
large_client_header_buffers 4 500k;

# Mitigate httpoxy attack
proxy_set_header Proxy "";

server {
    client_max_body_size 100M;
    listen 80;
    access_log /var/log/nginx/access.log vhost;

    # Here is the main BTCPay Server application
    location / {
        proxy_pass http://127.0.0.1:23000;
    }
}
EOF

##### Load global environment variables #####
source ~/globals.env

##### Install bitcoind #####
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
# Changed permissions from 0710 to 0755 for lightnind
StateDirectoryMode=0755

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
# Set database cache size in MB (The minimum value is 4; default is 450).
dbcache=256
# Reduce storage requirements by only storing this many MBs of the most recent blocks (The minimum value is 550).
prune=550

# [network]
# Connect only to the specified node and nothing else.
connect=$BTC_NODE_IP
# Accept incoming connections from peers.
listen=0

# [rpc]
# Accept command line and JSON-RPC commands. (nbxplorer)
server=1
# Username (satoshi) and hashed password (satoshi) for JSON-RPC connections.
rpcauth=satoshi:170f4d25565cfe8cbd3ab1c81ad25610$a8327a4d2241c121e0cd88d1b693cdc6aa3dfbcebb6b863545d090f5d7fa614b
EOF
sudo chown root:bitcoin /etc/bitcoin.conf
sudo chmod 644 /etc/bitcoin.conf

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

##### Install nbxplorer #####
cd ~; git clone https://github.com/dgarage/NBXplorer # Don't use sudo! we want the directory to be owned by satoshi.
cd NBXplorer
git checkout $(git tag --sort -version:refname | awk 'match($0, /^v[0-9]+\./)' | head -n 1)
sudo ./build.sh

sudo -i -u postgres psql -c "CREATE DATABASE nbxplorer TEMPLATE 'template0' LC_CTYPE 'C' LC_COLLATE 'C' ENCODING 'UTF8'"
sudo -i -u postgres psql -c "CREATE USER nbxplorer WITH ENCRYPTED PASSWORD 'nbxplorer'"
sudo -i -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE nbxplorer TO nbxplorer"

cd ~; mv NBXplorer .nbxplorer

# Create NBXplorer Configuration File
sudo mkdir /etc/nbxplorer
cat << EOF | sudo tee /etc/nbxplorer/nbxplorer.config
### Database ###
postgres=User ID=nbxplorer;
Password=nbxplorer;
Application Name=nbxplorer;
MaxPoolSize=20;
Host=localhost;
Port=5432;
Database=nbxplorer;
EOF
sudo chmod 644 /etc/nbxplorer/nbxplorer.config

# Create NBXplorer Systemd File
cat << EOF | sudo tee /etc/systemd/system/nbxplorer.service
[Unit]
Description=NBXplorer Daemon
Requires=bitcoind.service
After=bitcoind.service

[Service]
WorkingDirectory=/home/satoshi/.nbxplorer
ExecStart=/home/satoshi/.nbxplorer/run.sh --conf=/etc/nbxplorer/nbxplorer.config
User=satoshi
Group=satoshi
Type=simple
PIDFile=/run/nbxplorer/nbxplorer.pid
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

##### Install btcpay #####
cd ~; git clone https://github.com/btcpayserver/btcpayserver.git # Don't use sudo! we want the directory to be owned by satoshi.
cd btcpayserver
git checkout $(git tag --sort -version:refname | awk 'match($0, /^v[0-9]+\.[0-9]+\.[0-9]+$/)' | head -n 1)
./build.sh

sudo -i -u postgres psql -c "CREATE DATABASE btcpay TEMPLATE 'template0' LC_CTYPE 'C' LC_COLLATE 'C' ENCODING 'UTF8'"
sudo -i -u postgres psql -c "CREATE USER btcpay WITH ENCRYPTED PASSWORD 'btcpay'"
sudo -i -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE btcpay TO btcpay"

cd ~; mv btcpayserver .btcpayserver

# Create btcpay Configuration File
sudo mkdir /etc/btcpay
cat << EOF | sudo tee /etc/btcpay/btcpay.config
### Database ###
postgres=User ID=btcpay;
Password=btcpay;
Application Name=btcpayserver;
Host=localhost;
Port=5432;
Database=btcpay;
explorer.postgres=User ID=nbxplorer;
Password=nbxplorer;
Application Name=nbxplorer;
MaxPoolSize=20;
Host=localhost;
Port=5432;
Database=nbxplorer;
EOF
sudo chmod 644 /etc/btcpay/btcpay.config

# Create btcpay Systemd File
cat << EOF | sudo tee /etc/systemd/system/btcpay.service
[Unit]
Description=BTCPay Server
Requires=nbxplorer.service
After=nbxplorer.service

[Service]
WorkingDirectory=/home/satoshi/.btcpayserver
ExecStart=/home/satoshi/.btcpayserver/run.sh --conf=/etc/btcpay/btcpay.config
User=satoshi
Group=satoshi
Type=simple
PIDFile=/run/btcpayserver/btcpayserver.pid
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

##### Install Core Lightning Daemon #####
# Download Core Lightning, Verify Checksum, and Install
cat << EOF
See list of Core Lightning Releases @ https://github.com/ElementsProject/lightning/releases
The latest (workable on Debian) release as of 12/12/2024 listed below:

# clightning-v24.11, amd64 (Ubuntu-22.04)
    SOURCE: https://github.com/ElementsProject/lightning/releases/download/v24.11/clightning-v24.11-Ubuntu-22.04-amd64.tar.xz
    CHECKSUM: 38d3644bbd5b336d0541e3a7c6cd07278404da824471217bd5498b86a98d56d7
EOF
read -p "Core Lightning URL (.tar.xz) source: " SOURCE
read -p "SHA 256 Checksum for the .tar.xz source file: " CHECKSUM

sudo wget $SOURCE
if ! [ -f ~/${SOURCE##*/} ]; then echo "Error: Could not download source!"; exit 1; fi
if [[ ! "$(sha256sum ~/${SOURCE##*/})" == *"$CHECKSUM"* ]]; then
    echo "Error: SHA 256 Checksum for file \"~/${SOURCE##*/}\" was not what was expected!"
    exit 1
fi
sudo tar -xvf ${SOURCE##*/} -C /usr/local --strip-components=2
sudo rm ${SOURCE##*/}

# Create lightning System User
sudo useradd --system --shell=/sbin/nologin lightning

# Prepare Service Configuration
cat << EOF | sudo tee /etc/systemd/system/lightningd.service
[Unit]
Description=Core Lightning Daemon
Wants=network-online.target
After=network-online.target
After=btc-node-autossh.service

[Service]
ExecStart=/usr/local/bin/lightningd --conf /etc/lightningd.conf --pid-file /run/lightningd/lightningd.pid

Type=simple
PIDFile=/run/lightningd/lightningd.pid
Restart=on-failure

### Creates /run/lightningd owned by lightning ###
RuntimeDirectory=lightningd

### Run as lightning:lightning ###
User=lightning
Group=lightning

### Hardening Measures ###
PrivateTmp=true
ProtectSystem=full
NoNewPrivileges=true
PrivateDevices=true
MemoryDenyWriteExecute=true

[Install]
WantedBy=multi-user.target
EOF

# Core lightningd will look for bitcoin.conf in /var/lib/bitcoin
sudo ln -s /etc/bitcoin.conf /var/lib/bitcoin/bitcoin.conf

# Generate Core Lightning Configuration File with the Appropriate Permissions
cat << EOF | sudo tee /etc/lightningd.conf
# Select the network
network=bitcoin
# Run in the background
daemon
# Set base directory
lightning-dir=/var/lib/lightningd
# Amount to leave in wallet for spending anchor closes (default: 25000000)
min-emergency-msat=0

############## LND Node Configuration ##############
# RRGGBB hex color for node
rgb=000000
# Up to 32-byte alias for node
alias=Private btcpay Server

############## Bitcoin Node ##############
# datadir arg for bitcoin-cli
bitcoin-datadir=/var/lib/bitcoin
# bitcoind RPC username
bitcoin-rpcuser=satoshi
# bitcoind RPC password
bitcoin-rpcpassword=satoshi
# bitcoind RPC host to connect to
bitcoin-rpcconnect=127.0.0.1

############## Logging ##############
# log level (io, debug, info, unusual, broken) [:prefix] (default: info)
log-level=debug
# Log to file (- for stdout)
log-file=/var/log/lightningd/log

############## Channel Creation Policy ##############
# Minimum fee to charge for every (incomming) payment which passes through (in HTLC) (millisatoshis; 1/1000 of a satoshi) (default: 1000)
fee-base=0
# Microsatoshi fee for every satoshi in HTLC (10 is 0.001%, 100 is 0.01%, 1000 is 0.1% etc.) (default: 10)
fee-per-satoshi=0

############## Network ##############
# Set an IP address and port to listen on
bind-addr=0.0.0.0:9735
EOF
sudo chown root:lightning /etc/lightningd.conf
sudo chmod 640 /etc/lightningd.conf

# Create lightning & bitcoin directory
sudo mkdir -p /var/lib/lightningd
sudo chown root:lightning -R /var/lib/lightningd
sudo chmod 670 -R /var/lib/lightningd

# Create lightningd log file location /w appropriate permissions
sudo mkdir -p /var/log/lightningd
sudo chown root:lightning -R /var/log/lightningd
sudo chmod 670 -R /var/log/lightningd

# Configure lightningd's Log file from Filling up the partition
cat << EOF | sudo tee /etc/logrotate.d/lightningd
/var/log/lightningd/log {
$(printf '\t')create 660 root lightning
$(printf '\t')daily
$(printf '\t')rotate 14
$(printf '\t')compress
$(printf '\t')delaycompress
$(printf '\t')sharedscripts
$(printf '\t')postrotate
$(printf '\t')$(printf '\t')killall -HUP lightningd
$(printf '\t')endscript
}
EOF

# Establish alias for lightning-cli
echo $'alias lncli="sudo -u lightning lightning-cli --conf=/etc/lightningd.conf"' | sudo tee -a /etc/bash.bashrc

##### Reload/Enable System Control for new processes #####
sudo systemctl daemon-reload
sudo systemctl enable bitcoind
sudo systemctl enable nbxplorer
sudo systemctl enable btcpay
sudo systemctl enable lightningd

##################### Watch tower for the main node. ???????????????????????? What's the plan for c??????????????????
# Create links (for backup purposes) to all critical files needed to restore this node ##################### What do we do when we can't loose any data whatsoever???????????????????????? What's the plan??????????????????
# cd ~; mkdir backup
# sudo ln -s /var/lib/bitcoin/satoshi_coins ~/backup
# sudo ln -s /var/lib/bitcoin/mining ~/backup
# sudo ln -s /var/lib/bitcoin/bank ~/backup
# sudo ln -s /root/passphrase ~/backup
# sudo ln -s /etc/default/send_messages.env ~/backup
# sudo ln -s /var/log/satoshi_coins/log ~/backup

# If "~/restore" folder is present then restore all pertinent files; assumes all files are present
# if [[ -d ~/restore ]]; then
    # Restore ownership to files
#     sudo chown -R bitcoin:bitcoin ~/restore/satoshi_coins
#     sudo chown -R bitcoin:bitcoin ~/restore/mining
#     sudo chown -R bitcoin:bitcoin ~/restore/bank
#     sudo chown root:root ~/restore/passphrase
#     sudo chown root:root ~/restore/send_messages.env
#     sudo chown root:root ~/restore/log

    # Move files to their correct locations
#     sudo systemctl stop bitcoind; echo "Waiting 30 seconds for bitcoind to shutdown..."; sleep 30
#     sudo rm -rf /var/lib/bitcoin/satoshi_coins
#     sudo rm -rf /var/lib/bitcoin/mining
#     sudo rm -rf /var/lib/bitcoin/bank
#     sudo mv -f ~/restore/satoshi_coins /var/lib/bitcoin
#     sudo mv -f ~/restore/mining /var/lib/bitcoin
#     sudo mv -f ~/restore/bank /var/lib/bitcoin
#     sudo mv ~/restore/passphrase /root/passphrase
#     sudo mv ~/restore/send_messages.env /etc/default/send_messages.env
#     sudo mv ~/restore/log /var/log/satoshi_coins/log

    # Remove the "~/restore" folder
#     cd ~; sudo rm -rf restore
# fi

# Install send_messages and a script that constantly unloads the funds to the main lightning node when hit a certain amount. sends all the funds away????????????????????????????

# Restart the machine
sudo reboot now