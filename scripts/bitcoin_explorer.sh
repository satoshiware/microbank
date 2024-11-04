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
cat << EOF | sudo tee ~/readme.txt
This readme was generated by the "btc-explorer.sh", a "Bitcoin Blockchain Explorer" install script.
    Install Directory: /usr/local/lib/node_modules/btc-rpc-explorer
    Cache Directory: /var/lib/btc-rpc-explorer/cache
    Environment File: /etc/btc-rpc-explorer/.env
    Log Information: sudo journalctl -f -a -u btc-rpc-explorer
                     sudo journalctl -a -u btc-rpc-explorer
    Status Information: sudo systemctl status btc-rpc-explorer
    Run Manually: sudo -u btcexp btc-rpc-explorer

    HTTP Port: 0.0.0.0:3002
    Note: BTC Explorer is configured to operate with a reverse proxy.
EOF

# Install packages
sudo apt-get -y install nodejs npm

# Load global environment variables
source ~/globals.env

# Create a btc-rpc-explorer System User (btcexp) and home folder
sudo useradd --system --shell=/sbin/nologin btcexp

# Install btc-rpc-explorer
cd ~; git clone https://github.com/janoside/btc-rpc-explorer
cd btc-rpc-explorer
sudo npm -g install # Installs module in /usr/local/lib/node_modules/btc-rpc-explorer

# Create /var/lib directory (used to store cache fore btc-rpc-explorer)
sudo mkdir -p /var/lib/btc-rpc-explorer
sudo chown -R btcexp:btcexp /var/lib/btc-rpc-explorer
sudo chmod 700 /var/lib/btc-rpc-explorer

# Configure .env variables
sudo mkdir -p /etc/btc-rpc-explorer
sudo mv ~/btc-rpc-explorer/.env-sample /etc/btc-rpc-explorer/.env
rm -rf ~/btc-rpc-explorer # Delete github directory
cat << EOF | sudo tee -a /etc/btc-rpc-explorer/.env
################### Custom Configureation Below ############################
# Set true so the express app will also have "trust proxy" set to 1, to help run this tool behind the HTTPS reverse proxy
BTCEXP_SECURE_SITE=true

# The active coin. Only officially supported value is "BTC".
# Default: BTC
#BTCEXP_COIN=BTC

# Bind to any ipv4 for the http server on port 3002 (NO COMMENT ALLOWED FOLLOWING BTC_HOST EXPRESSION)
BTCEXP_HOST=0.0.0.0

# Bitcoin RPC Credentials
BTCEXP_BITCOIND_HOST=$BTC_NODE_LOCAL
BTCEXP_BITCOIND_USER=satoshi
BTCEXP_BITCOIND_PASS=satoshi

# Enable and configure Electrum to display address tx lists and balances
BTCEXP_ADDRESS_API=electrum
BTCEXP_ELECTRUM_SERVERS=tcp://$BTC_ELECTRUM_LOCAL:50001

# Enable resource-intensive features, including: UTXO set summary querying
BTCEXP_SLOW_DEVICE_MODE=false

# Disables Exchange-rate queries, IP-geolocation queries, etc.
BTCEXP_PRIVACY_MODE=true

# Configure cache directory
BTCEXP_FILESYSTEM_CACHE_DIR=/var/lib/btc-rpc-explorer/cache

# Set default currency to SATS
BTCEXP_DISPLAY_CURRENCY=sat

# Show local time instead of UTC
BTCEXP_UI_TIMEZONE=local

# UI Option: Hide info notes
BTCEXP_UI_HIDE_INFO_NOTES=true
EOF

# Create systemd service file
cat << EOF | sudo tee /etc/systemd/system/btc-rpc-explorer.service
[Unit]
Description=Bitcoin Block Explorer
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/bin/npm --prefix /usr/local/lib/node_modules/btc-rpc-explorer run start

Type=simple
Restart=always
RestartSec=30
TimeoutStartSec=infinity

### Run as btcexp:btcexp ###
User=btcexp
Group=btcexp

### Hardening measures ###
PrivateTmp=true
ProtectSystem=full
NoNewPrivileges=true
PrivateDevices=true

[Install]
WantedBy=multi-user.target
EOF

# Reload/Enable System Control for new processes
sudo systemctl daemon-reload
sudo systemctl enable btc-rpc-explorer

# Restart the machine
sudo reboot now