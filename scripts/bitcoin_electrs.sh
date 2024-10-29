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
This readme was generated by the "bitcoin_electrs.sh" install script.
A bitcoin electrum (electrs by Blockstream) node has been installed and readied to receive connections from external services.

The "/var/lib/electrs" directory contains debug logs, rocks DB, etc.
The electrs' log files can be viewed with this file: "/var/log/electrs/debug.log" (links to /var/lib/electrs/mainnet/newindex/txstore/LOG)
The "sudo systemctl status electrs" command shows the status of the electrs daemon.
The "sudo journalctl (-f) -a -u electrs" command shows the electrs journal.

Ports:
    HTTP Server: 3000 from any IP
    JSON RPC: 50001 from any IP
    Prometheus monitoring: 4224 from the localhost

Connect to prometheus monitoring daemon via port forwarding:
    ssh -L 9090:localhost:9090 satoshi@$(hostname) -i \$HOME\.ssh\Yubikey
    It can be reached on the browser @ http://localhost:9090
    Relevant prometheus commands: daemon*, mempool*, tip_height, elect*, query*
EOF

# Run latest updates and upgrades
sudo apt-get -y update
sudo DEBIAN_FRONTEND=noninteractive apt-get -y install --only-upgrade openssh-server # Upgrade seperatly to ensure non-interactive mode
sudo apt-get -y upgrade

# Install Packages
sudo apt-get -y install ufw clang psmisc prometheus
curl https://sh.rustup.rs -sSf | sh -s -- -y
export PATH=$PATH:~/.cargo/bin

# Load global environment variables
source ~/globals.env

# Configure Prometheus to connect to electrs' monitoring port
cat << EOF | sudo tee -a /etc/prometheus/prometheus.yml
  - job_name: electrs
    static_configs:
      - targets: ['localhost:4224']
EOF

# Authorize Yubikey login for satoshi
echo $YUBIKEY | sudo tee -a ~/.ssh/authorized_keys

# Download electrs, Compile, and Install
cd ~; git clone https://github.com/Blockstream/electrs
cd electrs
cargo clean; cargo build --locked --release
sudo install -m 0755 -o root -g root -t /usr/bin ~/electrs/target/release/electrs
cd ~; rm -rf electrs

# Prepare Service Configuration
cat << EOF | sudo tee /etc/systemd/system/electrs.service
[Unit]
Description=electrs
After=network-online.target

[Service]
WorkingDirectory=/var/lib/electrs
# Prefix address search enabled: --address-search
# Indexing of provably unspendable outputs enabled: --index-unspendables
# Perform compaction during initial sync (slower but less disk space required): --index-unspendables
# Use JSONRPC instead of importing blk*.dat files. Required for remote connections: --jsonrpc-import
# Prepend log lines with a timestamp: --timestamp
# Increase logging verbosity: -v
# Select the network of choice: --network mainnet
# The listening RPC address:port of bitcoind: --daemon-rpc-addr $BTC_NODE_IP:8332
# Directory where the index will be stored: --db-dir /var/lib/electrs
# HTTP server 'addr:port' to listen on: --http-addr 0.0.0.0:3000
# JSON RPC for electrs will listen to all IPs on port 50001: --electrum-rpc-addr 0.0.0.0:50001
# Bitcoin JSON RPC authentication: --cookie satoshi:satoshi
# Maximum number of transactions [default: 500] returned (does not apply for the http api). Lookups with more results will fail: --electrum-txs-limit 500
# Maximum number of utxos [default: 500] to process per address (applies to both electrum & http api). Lookups for addresses with more utxos will fail: --utxos-limit 500
# Number of JSONRPC requests [default: 4] to send in parallel: --daemon-parallelism 4
# Select RPC logging option: --electrum-rpc-logging full
ExecStart=/usr/bin/electrs \
    -vvvv \
    --address-search \
    --index-unspendables \
    --initial-sync-compaction \
    --jsonrpc-import \
    --timestamp \
    --daemon-rpc-addr $BTC_NODE_IP:8332 \
    --db-dir /var/lib/electrs \
    --http-addr 0.0.0.0:3000 \
    --electrum-rpc-addr 0.0.0.0:50001 \
    --cookie satoshi:satoshi \
    --electrum-txs-limit 500 \
    --utxos-limit 500 \
    --daemon-parallelism 4 \
    --electrum-rpc-logging full

Type=simple
KillMode=process
TimeoutSec=240
Restart=always
RestartSec=30

Environment="RUST_BACKTRACE=1"
LimitNOFILE=1048576

### Run as electrs:electrs ###
User=electrs
Group=electrs

### /var/lib/electrs ###
StateDirectory=electrs
StateDirectoryMode=0710

### Hardening measures ###
PrivateTmp=true
ProtectSystem=full
NoNewPrivileges=true
MemoryDenyWriteExecute=true
PrivateDevices=true

[Install]
WantedBy=multi-user.target
EOF

# Create a electrs System User
sudo useradd --system --shell=/sbin/nologin electrs

# Setup a Symbolic Link to Standardize the Location of electrs' Log Files
sudo mkdir -p /var/log/electrs
sudo ln -s /var/lib/electrs/mainnet/newindex/txstore/LOG /var/log/electrs/debug.log

# Install/Setup/Enable the Uncomplicated Firewall (UFW)
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh # Open Default SSH Port
sudo ufw allow 3000 # Open up Electrs HTTP server
sudo ufw allow 50001 # Open Electrs JSON RPC connection access
sudo ufw --force enable # Enable Firewall @ Boot and Start it now!

# Reload/Enable System Control for new processes
sudo systemctl daemon-reload
sudo systemctl enable electrs

# Restart the machine
sudo reboot now