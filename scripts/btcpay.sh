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

##### Give the user pertinent information about this script and how to use it. #####
cat << EOF | sudo tee ~/readme.txt
This readme was generated by the "btcpay.sh" install script.

There are 4 programs installed in order to make the btcpay server operate: Core Lightning, BTC Pruned Node, and NBXplorer.
Because the Core Lightning software still requires access to the bitcoin-cli utility, the BTC Pruned Node is also installed.
It may very well be removed in the future. The NBXplorer is similar to the electrum server, but has been optimized for
extended public keys; perhaps this software isn't necessary either and with future Electrum Server upgrades, it can also be
removed. The litu utility aids in creating bolt12 invoices, sending funds to the main lightning node, and notifying the
administrator.

Network & Post Configuration:
    Port 9735 is only accessible from the local network only. It is not exposed to the internet.
    send_messages --generate # (Re)Generate(s) the environment file (w/ needed constants) for the send_messages utility
    Add the Bank's main lightning node's ID to the file /var/log/lightningd/private_channels

Log locations:
    Bitcoin: /var/log/bitcoin/debug.log
    BTCPay: /var/log/btcpay/debug*.log
    Core Lightning: /var/log/lightningd/log

Files:
    /etc/bitcoin.conf # Bitcoin Configureation File
    /etc/lightningd.conf # Core Lightningd Configureation File
    /var/lib/bitcoin # Bitcoin directory containing debug logs, blockchain, etc.
    /var/lib/lightningd" # Lightningd Var Directory
    /home/satoshi/.btcpayserver # BTC Pay install directory
    /home/satoshi/.nbxplorer # NBXplorer install directory

View Statuses & Logs Via Systemd:
    Bitcoin:
        sudo systemctl status bitcoind
        sudo journalctl -f -a -u bitcoind
    BTCPay:
        sudo systemctl status btcpay
        sudo journalctl -f -a -u btcpay
    Core Lightning:
        sudo systemctl status lightningd
        sudo journalctl -f -a -u lightningd
    NBXplorer:
        sudo systemctl status nbxplorer
        sudo journalctl -f -a -u nbxplorer

Debugging & Useful Commands:
    bitcoind:
        btc --help # List all runtime configurations
        btc help # List all RPC commands
        btc help <command> # Get information about a specific RPC command
    lightningd:
        lncli # See list of commands
        lncli getinfo # Show all the information about this node
        lncli getlog debug # Show log with all debug messages
        lncli listfunds # Display all funds available, either in unspent outputs (UTXOs) in the internal wallet or funds locked in currently open channels
        lncli listnodes # Ensure nodes are visible. This information is aquired via the gossip network
        lncli listchannels null \$(lncli getinfo | jq -r .id) null # Show "source" channels coming into this node
        lncli listchannels null null \$(lncli getinfo | jq -r .id) # Show "destination" channels coming into this node
    nbxplorer:
        cd ~/.nbxplorer; ./run.sh --help # List all potential configurations
        # Start the service manually to look for any error messages
            sudo systemctl stop nbxplorer
            cd ~/.nbxplorer; ./run.sh
    btcpay:
        cd ~/.btcpayserver; ./run.sh --help # List all potential configurations
        # Start the service manually to look for any error messages
            sudo systemctl stop btcpay
            cd ~/.btcpayserver; ./run.sh

nbxplorer REST API Access (via Postman web interface; see "https://github.com/dgarage/NBXplorer" for more information)
    # Make port 24444 accessible on 14444 via port forwarding. Note: Make sure you have access on the router
    ssh -L 14444:localhost:24444 satoshi@$(ip address show | grep "inet " | tail -n 1 | xargs | cut -d " " -f 2 | cut -d "/" -f 1) -i ~/.ssh/Yubikey
    # URL for Web Page Access. Note: Cookie authentication is disabled.
    http://localhost:14444

Post Install BTCPAY Configuration
    Setup Reverse Proxy to point to port 23000 for BTCPAY server access (e.g. https://btcpay.\$YOUR_BANK_DOMAIN.com)
    Connect to BTCPAY Server
        Setup Administrator Account:
            User: satoshi@\$YOUR_BANK_DOMAIN.com
            Passwd: satoshi
        Create First Store (w/ Default Currency as \$ATS)
            Setup Bittcoin Wallet (Use External "Extended Public Key" Only)
                Get the "Extended Public Key" from the "btc-wallet" node using the "wallu" utility
                Verify Address Generation
                Note: If the wallet (i.e. "Extended Public Key") has already been used (e.g. we are rebuilding the btcpay server w/ existing wallet) be sure to re-scan with
                    an apropriate gap limit (e.g. 25K). Once complete, BTCPay Server will show the correct balance, along with the past transactions of the wallet.
            Lightning Node Setup: Select "Use internal node"
                Enable "Display Lightning payment amounts in Satoshis"
                Enable "Add hop hints for private channels to the Lightning invoice"
                Description Template: "Paid to {StoreName} for {ItemDescription} (Order ID: {OrderId})"
            Configure Store Checkout (Settings > Checkout Experience)
                "Default payment method on checkout": BTC-LN
                "Select a preset": Online
                "Enable payment methods only when amount is …"
                    BTC-LN      "Less than"         0.040 BTC
                    BTC-CHAIN   "Greater than"      0.03999999 BTC
            Add Another Store Owner (Settings > Users)
                Note: Follow up and make sure new owner implements proper security measures for authentication.
        Create Lightning Address (PLUGINS > Lightning Address) (e.g. satoshi@btcpay.\$YOUR_BANK_DOMAIN.com w/ "invoice currency" = sats the rest blank)
        Setup FIDO2 Two-Factor Authentication (Account > Two-Factor Authentication) (e.g. Yubikey)
        Confire Server Email (Server Settings > Email)
            Create unique password with SMTP Relay (e.g. brevo.com)
        Configure Block Explorer (Server Settings > Block Explorers) (e.g. https://btc-explorer.\$YOUR_BANK_DOMAIN.com/tx/{0})
        Configure BTCPAY Server Name and Contact URL (Server Settings > Branding)

BTCPAY Access
    Webpage: https://btcpay.\$YOUR_BANK_DOMAIN.com
    User: satoshi@\$YOUR_BANK_DOMAIN.com
    Passwd: satoshi

BTCPAY FIDO2 Reset for satoshi@\$YOUR_BANK_DOMAIN.com
    # Login to the btcpay server via ssh and execute the following
    ADMIN_EMAIL="satoshi@\$YOUR_BANK_DOMAIN.com"
    sudo -i -u postgres psql -d btcpay -c "DELETE FROM \"Fido2Credentials\" WHERE \"ApplicationUserId\" = (SELECT \"Id\" FROM \"AspNetUsers\" WHERE upper('\$ADMIN_EMAIL') = \"NormalizedEmail\")"

Create (5M SAT) Channel from the bank's primary lightning node
    lncli getinfo | jq -r .id                                                                   # Get BTCPAY's lightning Node ID (\$PEER_ID)
    ip address show | grep "inet " | tail -n 1 | xargs | cut -d " " -f 2 | cut -d "/" -f 1      # Get IP address (\$LOCAL_IP_ADDRESS)
    ##### Execute these commands on the bank's primary lightning node #####
    litu --private_channel \$PEER_ID \$LOCAL_IP_ADDRESS 5000000 BTCPAY                            # Execute this command on the bank's primary lightning node to open channel
    lncli setchannel \$PEER_ID 0 0                                                               # Execute this command on the bank's primary lightning node to reduce all fees to 0

Upgrading Core Lightning:
    Upgrading your Core Lightning node is the same as installing it. Download the latest binary in the same directory as before. Example:
        sudo systemctl disable lightningd
        lncli stop
        LIGHTNING_CORE_SOURCE="https://github.com/ElementsProject/lightning/releases/download/v24.11/clightning-v24.11-Ubuntu-22.04-amd64.tar.xz"
        LIGHTNING_CORE_CHECKSUM="38d3644bbd5b336d0541e3a7c6cd07278404da824471217bd5498b86a98d56d7"
        cd ~; sudo wget \$LIGHTNING_CORE_SOURCE # Download Core Lightning Binaries
        sha256sum ~/\${LIGHTNING_CORE_SOURCE##*/} # Verify Checksum Matches
        sudo tar -xvf \${LIGHTNING_CORE_SOURCE##*/} -C /usr/local --strip-components=2 # Install binaries in the appropriate directory
        sudo rm \${LIGHTNING_CORE_SOURCE##*/} # Clean up.
        sudo systemctl enable lightningd --now

Backup/Restore:
    WARNING! If you intend to backup/restore the lightningd database, know that snapshot-style backups of the lightningd database is discouraged,
    as any loss of state may result in permanent loss of funds! If you are to continue, first disable and stop (i.e. shutdown) lightningd:
        sudo systemctl disable lightningd
        sudo systemctl stop lightningd
    Then make sure the files "lightningd.sqlite3" and "lightningd.sqlite3.backup" appear the same (time & date) in "/var/lib/lightningd/bitcoin/":

    Even though the postgresql (btcpay and nbxplorer) database is backed up daily, be sure to capture the latest with the following command:
        sudo -i -u postgres pg_dumpall -c | gzip > ~/backup/postgres_dump.sql.gz

    IMPORTANT! Don't forget to run the backup script one last time to capture the latest database changes (if any) and then continue as normal as with
    any other backup and restore process.

How-To Copy this BTC Pruned Node (Establish New Pruned Nodes Quickly)
    #### Create ~/bitcoin.tar.gz File ####
    sudo systemctl stop bitcoind
    sudo rm ~/bitcoin.tar.gz
    cd ~; sudo tar -czvf bitcoin.tar.gz /var/lib/bitcoin # Compress

    #### From the Host, Download bitcoin.tar.gz ####
    sudo rm ~/bitcoin.tar.gz
    cd ~; scp -i ~/.ssh/vmkey satoshi@btcpay.local:/home/satoshi/bitcoin.tar.gz .

    #### From the Host, Upload bitcoin.tar.gz to the NEW IMAGE ####
    NEW_IMGAGE=btcpay
    scp -i ~/.ssh/vmkey ~/bitcoin.tar.gz satoshi@\${NEW_IMGAGE}.local:/home/satoshi/bitcoin.tar.gz

    #### From the NEW IMAGE, Extract Files to Appropriate Location ####
    sudo rm -rf /var/lib/bitcoin
    cd ~; sudo tar -xvzf bitcoin.tar.gz -C /
    sudo rm bitcoin.tar.gz

    #### Create Bitcoin User and Set Ownership ####
    sudo useradd --system --shell=/sbin/nologin bitcoin # Create a bitcoin System User
    sudo chown -R bitcoin:bitcoin /var/lib/bitcoin
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
sudo apt-get -y install psmisc ufw jq apt-transport-https dotnet-sdk-8.0 postgresql postgresql-contrib xz-utils libpq5
sudo dotnet workload update # Updates all installed dotnet workloads to the newest available versions

# Install Pythong Modules
sudo apt-get -y install python3-pip python3-websockets python3-cryptography python3-gevent python3-gunicorn python3-flask python3-json5
sudo pip install pyln-client flask_restx flask_cors flask_socketio --break-system-packages

##### Install/Setup/Enable the Uncomplicated Firewall (UFW) #####
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh # Open Default SSH Port
sudo ufw allow 23000 # Open BTCPay Server Port
sudo ufw allow from $(hostname -I | cut -d "." -f 1,2,3).0/24 to any port 9735 # Open Default lightningd Port for local network only
sudo ufw --force enable # Enable Firewall @ Boot and Start it now!

##### Load global environment variables #####
source ~/globals.env

# Authorize Yubikey login for satoshi
echo $YUBIKEY | sudo tee -a ~/.ssh/authorized_keys

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
# Accept command line and JSON-RPC commands.
server=1
# Username (satoshi) and hashed password (satoshi) for JSON-RPC connections.
rpcauth=satoshi:170f4d25565cfe8cbd3ab1c81ad25610\$a8327a4d2241c121e0cd88d1b693cdc6aa3dfbcebb6b863545d090f5d7fa614b
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

##### Install nbxplorer #####
cd ~; git clone https://github.com/dgarage/NBXplorer # Don't use sudo! we want the directory to be owned by satoshi.
cd NBXplorer
git checkout $(git tag --sort -version:refname | awk 'match($0, /^v[0-9]+\./)' | head -n 1)
sudo ./build.sh
cd ~; mv NBXplorer .nbxplorer

# Create postgresql Database /w its own schema (for security)
sudo -i -u postgres psql -c "CREATE DATABASE nbxplorer TEMPLATE 'template0' LC_CTYPE 'C' LC_COLLATE 'C' ENCODING 'UTF8'"
sudo -i -u postgres psql -c "CREATE USER nbxplorer WITH ENCRYPTED PASSWORD 'nbxplorer'"
sudo -i -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE nbxplorer TO nbxplorer"
sudo -i -u postgres psql << EOF
\c nbxplorer postgres;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
CREATE SCHEMA nbxplorer;
GRANT ALL ON SCHEMA nbxplorer TO nbxplorer;
EOF

# Create NBXplorer Configuration File
sudo mkdir /etc/nbxplorer
cat << EOF | sudo tee /etc/nbxplorer/nbxplorer.config
### Database ###
postgres="UserName=nbxplorer;Password=nbxplorer;ApplicationName=nbxplorer;MaxPoolSize=20;Host=localhost;Port=5432;Database=nbxplorer"

### bitcoind Remote Connection ###
btcrpcuser=satoshi
btcrpcpassword=satoshi
btcrpcurl=http://$BTC_NODE_IP:8332
btcnodeendpoint=$BTC_NODE_IP:8333

### Disable Cookie Authentication ###
NBXPLORER_NOAUTH=1
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
cd ~; mv btcpayserver .btcpayserver

# Create postgresql Database
sudo -i -u postgres psql -c "CREATE DATABASE btcpay TEMPLATE 'template0' LC_CTYPE 'C' LC_COLLATE 'C' ENCODING 'UTF8'"
sudo -i -u postgres psql -c "CREATE USER btcpay WITH ENCRYPTED PASSWORD 'btcpay'"
sudo -i -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE btcpay TO btcpay"
sudo -i -u postgres psql << EOF # TODO: MAKE THIS A PRIVATE SCHEMA (e.g. nbxplorer) WHEN BTCPAY SERVER SUPPORTS IT.
\c btcpay postgres;
GRANT ALL ON SCHEMA public TO btcpay;
EOF

# Setup cron job to backup postgresql database (both btcpay and nbxplorer) everyday
echo "sudo -i -u postgres pg_dumpall -c | gzip > ~/backup/postgres_dump.sql.gz" | sudo tee /usr/local/sbin/backup_postgresql > /dev/null
sudo chmod +x /usr/local/sbin/backup_postgresql
(crontab -l | grep -v -F "/usr/local/sbin/backup_postgresql" ; echo "0 0 * * * /bin/bash -lc \"/usr/local/sbin/backup_postgresql\"" ) | crontab -

# Create btcpay Configuration File
sudo mkdir /etc/btcpay
cat << EOF | sudo tee /etc/btcpay/btcpay.config
### Databases ###
postgres="UserName=btcpay;Password=btcpay;ApplicationName=btcpayserver;Host=localhost;Port=5432;Database=btcpay"
explorer.postgres="UserName=nbxplorer;Password=nbxplorer;ApplicationName=nbxplorer;MaxPoolSize=20;Host=localhost;Port=5432;Database=nbxplorer"

### Allow Incomming Connections from Anywhere ###
bind=0.0.0.0

### Configure Connection w/ Core Lightning ###
btclightning="type=clightning;server=unix://run/lightningd/lightning-rpc"

### Configure BTCPAY Logging ####
# A rolling log file for debug messages.
debuglog=/var/log/btcpay/debug.log
# The severity you log (default:information)
debugloglevel=debug
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

# Create BTCPAY log file location /w appropriate permissions
sudo mkdir -p /var/log/btcpay
sudo chown root:satoshi -R /var/log/btcpay
sudo chmod 670 -R /var/log/btcpay

# Configure BTCPAY's Log file from Filling up the partition
cat << EOF | sudo tee /etc/logrotate.d/btcpay
/var/log/btcpay/debug*.log {
$(printf '\t')create 660 root satoshi
$(printf '\t')daily
$(printf '\t')rotate 14
$(printf '\t')compress
$(printf '\t')delaycompress
$(printf '\t')sharedscripts
$(printf '\t')postrotate
$(printf '\t')$(printf '\t')create
$(printf '\t')endscript
}
EOF

##### Install Core Lightning Daemon #####
# Download Core Lightning, Verify Checksum, and Install
sudo wget $LIGHTNING_CORE_SOURCE
if ! [ -f ~/${LIGHTNING_CORE_SOURCE##*/} ]; then echo "Error: Could not download Core Lightning source!"; exit 1; fi
if [[ ! "$(sha256sum ~/${LIGHTNING_CORE_SOURCE##*/})" == *"$LIGHTNING_CORE_CHECKSUM"* ]]; then
    echo "Error: SHA 256 Checksum for file \"~/${LIGHTNING_CORE_SOURCE##*/}\" was not what was expected!"
    exit 1
fi
sudo tar -xvf ${LIGHTNING_CORE_SOURCE##*/} -C /usr/local --strip-components=2
sudo rm ${LIGHTNING_CORE_SOURCE##*/}

# Create lightning System User & Group; Add satoshi to the lightning Group
sudo useradd --system --shell=/sbin/nologin lightning
sudo usermod -a -G lightning satoshi

# Prepare Service Configuration
cat << EOF | sudo tee /etc/systemd/system/lightningd.service
[Unit]
Description=Core Lightning Daemon
Wants=network-online.target
After=network-online.target
After=btc-node-autossh.service

[Service]
ExecStart=/usr/local/bin/lightningd --conf /etc/lightningd.conf --pid-file /run/lightningd/lightningd.pid
ExecStop=/usr/local/bin/lightning-cli --conf=/etc/lightningd.conf stop

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

# Generate Core Lightning Configuration File with the Appropriate Permissions
cat << EOF | sudo tee /etc/lightningd.conf
# Select the network
network=bitcoin
# Run in the background
daemon
# Set base directory
lightning-dir=/var/lib/lightningd
# Lightningd Database Backup
wallet=sqlite3:///var/lib/lightningd/bitcoin/lightningd.sqlite3:/var/lib/lightningd/bitcoin/lightningd.sqlite3.backup

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
bitcoin-rpcconnect=$BTC_NODE_IP

############## Logging ##############
# log level (io, debug, info, unusual, broken) [:prefix] (default: info)
log-level=debug
# Log to file (- for stdout)
log-file=/var/log/lightningd/log

############## Channel Creation Policy ##############
# Minimum capacity in satoshis for accepting channels (default: 10000)
#min-capacity-sat=0 # Current Core Lightning version will not allow anything below the dust limit.
# Minimum fee to charge for every (incomming) payment which passes through (in HTLC) (millisatoshis; 1/1000 of a satoshi) (default: 1000)
fee-base=0
# Microsatoshi fee for every satoshi in HTLC (10 is 0.001%, 100 is 0.01%, 1000 is 0.1% etc.) (default: 10)
fee-per-satoshi=0

############## Network ##############
# Set an IP address and port to listen on
bind-addr=0.0.0.0:9735
# Set JSON-RPC socket location (default: "/var/lib/lightningd/bitcoin/lightning-rpc")
rpc-file=/run/lightningd/lightning-rpc
# Set the file mode (permissions) for the JSON-RPC socket (default: 0600)
rpc-file-mode=0660
EOF
sudo chown root:lightning /etc/lightningd.conf
sudo chmod 640 /etc/lightningd.conf

# Create lightning directory
sudo mkdir -p /var/lib/lightningd
sudo chown lightning:lightning -R /var/lib/lightningd
sudo chmod 710 -R /var/lib/lightningd

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
$(printf '\t')$(printf '\t')create
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

##### Install lightning node utilities #####
bash ~/microbank/scripts/litu.sh --install
bash ~/microbank/scripts/send_messages.sh --install

# Create links (for backup purposes) to all critical files needed to restore this node
cd ~; mkdir backup
sudo ln -s /var/lib/lightningd/bitcoin/hsm_secret ~/backup # HD wallet seed for On-chain funds stored in byte-form. Only need to backup once!
sudo ln -s /var/lib/lightningd/bitcoin/emergency.recover ~/backup # Each time a new channel is created, this file will need to be backed up anew.
    # Note: Static channel recovery file that requires cooperation with peers and should only be used as a last resort!
sudo ln -s /var/lib/lightningd/bitcoin/lightningd.sqlite3.backup ~/backup # Lightning daemon database backup
sudo ln -s /etc/default/send_messages.env ~/backup # Environment file for the send_messages utility

# If "~/restore" folder is present then restore all pertinent files; assumes all files are present
if [[ -d ~/restore ]]; then
    # Restore ownership to files
    sudo chown lightning:lightning ~/restore/hsm_secret
    sudo chown lightning:lightning ~/restore/emergency.recover
    sudo chown lightning:lightning ~/restore/lightningd.sqlite3.backup
    sudo chown satoshi:satoshi ~/restore/postgres_dump.sql.gz
    sudo chown root:root ~/restore/send_messages.env

    # Move files to their correct locations
    sudo mv ~/restore/hsm_secret /var/lib/lightningd/bitcoin/hsm_secret
    sudo mv ~/restore/emergency.recover /var/lib/lightningd/bitcoin/emergency.recover
    sudo mv ~/restore/lightningd.sqlite3.backup /var/lib/lightningd/bitcoin/lightningd.sqlite3.backup
    sudo mv ~/restore/send_messages.env /etc/default/send_messages.env

    echo ""
    echo "EXTREMELY IMPORTANT:"
    echo "    In order to restore the lightningd database, YOU MUST rename the file \"/var/lib/lightningd/bitcoin/lightningd.sqlite3.backup\""
    echo "    with the \".backup\" extension removed. THIS MAY CAUSE PERMANENT LOSS OF FUNDS IN THE CHANNELS if the restored backup was not the"
    echo "    absolute latest (i.e. does not contain the last states of the channels)! In other words, this backup, being restored, better be"
    echo "    one that was created intentionally (with the lightningd shutdown) just before this restore process began!"
    echo ""
    echo "    In order to restore the postgresql database (btcpay and nbxplorer), YOU MUST execute the following command:"
    echo "        gunzip -c ~/restore/postgres_dump.sql.gz | sudo -i -u postgres psql"
    echo "    Make sure the backup being restored is one that was created intentionally just before this restore process began! Backup CMD:"
    echo ""
    echo "Once finished, MANUALLY REBOOT THIS VM INSTANCE!"
    echo ""
    read -p "Press the enter key to continue..."

    # Remove the "~/restore" folder
    cd ~; sudo rm -rf restore
else
    sudo reboot now # Only restart the machine if the install did not restore from a backup
fi
