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

# Give the user pertinent information about this script and how to use it.?????????????????????????????????????????????????????????????????????????????????????????????
cat << EOF | sudo tee ~/readme.txt
This readme was generated by the "lightning_node.sh" install script.

Dependencies: Bitcoin Full Node connected via a Secure SSH Tunnel
	Before this connection will work, add the ssh key (sudo cat /root/.ssh/btc-node-autossh-key.pub)
	to the Bitcoin Full Node (sudo nano /home/btc-remote-cli/.ssh/authorized_keys)

Files:
    /etc/lightnind.conf # Core Lightningd Configureation File
	/var/lib/lightnind" # Lightningd Var Directory 
	/var/lib/bitcoin/bitcoin.conf # Bitcoin directory w/ bitcoin.conf file; both required for bitcoin-cli utility to run
	
	/root/.ssh/known_hosts # Contains the Bitcoin Full Node host key

    The "$USER/.ssh/authorized_keys" file contains administrator login keys.
    The "ext_rpc/.ssh/authorized_keys" file contains login keys for external services (lightning, electurm, stratum, and btcpay servers).


    The bitcoind's log files can be view with this file: "/var/log/bitcoin/debug.log" (links to /var/lib/bitcoin/debug.log)
    The "/var/lib/bitcoin/wallets" directory contains the various wallet directories.

    Passwords: /root/extrpcpasswd (External; user=ext_rpc), /root/lclrpcpasswd (Localhost; user=local_rpc), /root/strrpcpasswd (Stratum; user=stratum_rpc), and /root/passphrase (Wallet Passphrase)
    External RPC Ports: localhost:8332 (Bitcoin RPC), localhost:8433 (Bitcoin ZMQ)

    Bitcoin configuratijon: /etc/bitcoin.conf

Log: 
	sudo cat /var/log/lightningd/log

Info' Commands:
	sudo systemctl status btc-node-autossh # Show the SSH Tunnel to the Bitcoin Full Node status
	sudo systemctl status lightningd # Show the status of the lightning daemon
	sudo journalctl -a -u lightningd # Show system log for lightningd
	sudo journalctl -f -a -u lightningd # Show ROLLING system log for lightningd
	


    # announce-addr-discovered-port <arg>             NETWORK: Sets the public TCP port to use for announcing discovered IPs. (default: 9735)
    # bind-addr <arg>                                 NETWORK: Set an IP address (v4 or v6) to listen on, but not announce, to bind Core Lightning RPC server (default: 127.0.0.1:9734)
EOF
read -p "Press the enter key to continue..."

# Run latest updates and upgrades
sudo apt-get -y update
sudo DEBIAN_FRONTEND=noninteractive apt-get -y install --only-upgrade openssh-server # Upgrade seperatly to ensure non-interactive mode
sudo apt-get -y upgrade

# Install Packages
sudo apt-get -y install wget xz-utils libpq5 autossh

# Install Pythong Modules
sudo apt-get -y install python3-pip python3-websockets python3-cryptography python3-gevent python3-gunicorn python3-flask python3-json5
sudo pip install pyln-client flask_restx flask_cors flask_socketio --break-system-packages

# Load global environment variables
source ~/globals.env

# Download Bitcoin Core, Verify Checksum
sudo wget $BTC_CORE_SOURCE
if ! [ -f ~/${BTC_CORE_SOURCE##*/} ]; then echo "Error: Could not download source!"; exit 1; fi
if [[ ! "$(sha256sum ~/${BTC_CORE_SOURCE##*/})" == *"$BTC_CORE_CHECKSUM"* ]]; then
    echo "Error: SHA 256 Checksum for file \"~/${BTC_CORE_SOURCE##*/}\" was not what was expected!"
    exit 1
fi
sudo tar -xzf ${BTC_CORE_SOURCE##*/}
sudo rm ${BTC_CORE_SOURCE##*/}

# Install bitcoin-cli
sudo install -m 0755 -o root -g root -t /usr/bin bitcoin-*/bin/bitcoin-cli
sudo rm -rf bitcoin-*

# Generate public/private keys (non-encrytped)
sudo ssh-keygen -t ed25519 -f /root/.ssh/btc-node-autossh-key -N "" -C ""

# Create/Update known_hosts file with host key from the Bitcoin Node
sudo touch /root/.ssh/known_hosts
HOSTSIG=$(ssh-keyscan -p 22 -H $BTC_NODE_LOCAL)
echo "${HOSTSIG} # BTC NODE HOST KEY" | sudo tee -a /root/.ssh/known_hosts

# Create systemd service file for "Bitcoin Node Auto SSH Connection"
cat << EOF | sudo tee /etc/systemd/system/btc-node-autossh.service
[Unit]
Description=Bitcoin Node Auto SSH Connection
Before=lightningd.service
After=network-online.target

[Service]
Environment="AUTOSSH_GATETIME=0"
ExecStart=/usr/bin/autossh -M 0 -NT -o ServerAliveInterval=30 -o ExitOnForwardFailure=yes -o "ServerAliveCountMax 3" -i /root/.ssh/btc-node-autossh-key -L 8332:localhost:8332 -p 22 btc-remote-cli@$BTC_NODE_LOCAL

RestartSec=5
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Download Core Lightning, Verify Checksum, and Install
cat << EOF
See list of Core Lightning Releases @ https://github.com/ElementsProject/lightning/releases
The latest releases as of 12/12/2024 listed below:

# clightning-v24.11, amd64 (Ubuntu-22.04)
    https://github.com/ElementsProject/lightning/releases/download/v24.11/clightning-v24.11-Ubuntu-22.04-amd64.tar.xz
    38d3644bbd5b336d0541e3a7c6cd07278404da824471217bd5498b86a98d56d7

# clightning-v24.11, amd64 (Ubuntu-24.04)
    # NOTE: TOO ADVANCED FOR THE LATEST DEBIAN VERSION (BOOKWORM)
    # https://github.com/ElementsProject/lightning/releases/download/v24.11/clightning-v24.11-Ubuntu-24.04-amd64.tar.xz
    # 91246dabe5fa1b4b1dabd1f29e0e817bc6dc06d9f7a83e5c324e0f0c77122401
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

# Generate Core Lightning Configuration File with the Appropriate Permissions
cat << EOF | sudo tee /etc/lightningd.conf
# Set base directory
lightning-dir=/var/lib/lightningd
# Select the network
network=bitcoin
# Run in the background
daemon
# experimental-peer-storage                       EXPERIMENTAL: enable peer backup storage and restore
# RRGGBB hex color for node
rgb=$LIGHTNING_RGBHEX_COLOR
# Up to 32-byte alias for node
alias=${MICRO_BANK_NAME// /}
# Minimum fee to charge for every payment which passes through (in HTLC) (millisatoshis; 1/1000 of a satoshi) (default: 1000)
fee-base=1000
# Microsatoshi fee for every satoshi in HTLC (10 is 0.001%, 100 is 0.01%, 1000 is 0.1% etc.) (default: 10)
fee-per-satoshi=10
# max-concurrent-htlcs <arg>                      STD_SETTINGS: Maximum number of HTLCs one channel can handle, in each direction, concurrently. Should be between 1 and 483 (default: 30)
# max-dust-htlc-exposure-msat <arg>               STD_SETTINGS: Max HTLC amount that can be trimmed (default: 50000000)
# announce-addr <arg>                             NETWORK: Set an IP address (v4 or v6) or .onion v3 to announce, but not listen on, so peers can find your node (example: <IP/TOR ADDRESS>:9735)
# accept-htlc-tlv-type <arg>                      HTLC TLV type to accept (can be used multiple times)
# encrypted-hsm                                   Set the password to encrypt hsm_secret with. If no password is passed through command line, you will be prompted to enter it on startup
# force-feerates <arg>                            Set testnet/regtest feerates in sats perkw, opening/mutual_close/unlateral_close/delayed_to_us/htlc_resolution/penalty: if fewer specified, last number applies to remainder
# commit-fee <arg>                                Percentage of fee to request for their commitment (default: 100)
# commit-feerate-offset <arg>                     Additional feerate per kw to apply to feerate updates as the channel opener (default: 5)
# min-emergency-msat <arg>                        Amount to leave in wallet for spending anchor closes (default: 25000000)
# subdaemon <arg>                                 Arg specified as SUBDAEMON:PATH. Specifies an alternate subdaemon binary. If the supplied path is relative the subdaemon binary is found in the working directory. This option may be specified multiple times. For example, --subdaemon=hsmd:remote_signer would use a hypothetical remote signing subdaemon.
# invoices-onchain-fallback                       Include an onchain address in invoices and mark them as paid if payment is received on-chain
# log level (io, debug, info, unusual, broken) [:prefix] (default: info)
log-level=debug
# Log to file (- for stdout)
log-file=/var/log/lightningd/log
# datadir arg for bitcoin-cli
bitcoin-datadir=/var/lib/bitcoin
# bitcoind RPC username
bitcoin-rpcuser=satoshi
# bitcoind RPC password
bitcoin-rpcpassword=satoshi
# bitcoind RPC host to connect to
bitcoin-rpcconnect=$BTC_NODE_LOCAL

# funder-policy <arg>                             Policy to use for dual-funding requests. [match, available, fixed] (default: fixed)
# funder-policy-mod <arg>                         Percent to apply policy at (match/available); or amount to fund (fixed) (default: 0)
# funder-min-their-funding <arg>                  Minimum funding peer must open with to activate our policy (default: 10000sat)
# funder-max-their-funding <arg>                  Maximum funding peer may open with to activate our policy (default: 4294967295sat)
# funder-per-channel-min <arg>                    Minimum funding we'll add to a channel. If we can't meet this, we don't fund (default: 10000sat)
# funder-per-channel-max <arg>                    Maximum funding we'll add to a channel. We cap all contributions to this (default: 4294967295sat)
# funder-lease-requests-only <arg>                Only fund lease requests. Defaults to true if channel lease rates are being advertised (default: true)

# lease-fee-base-sat <arg>                        Channel lease rates, base fee for leased funds, in satoshi.
# lease-fee-basis <arg>                           Channel lease rates, basis charged for leased funds (per 10,000 satoshi.)
# lease-funding-weight <arg>                      Channel lease rates, weight we'll ask opening peer to pay for in funding transaction

# channel-fee-max-base-msat <arg>                 Channel lease rates, maximum channel fee base we'll charge for funds routed through a leased channel.
# channel-fee-max-proportional-thousandths <arg>  Channel lease rates, maximum proportional fee (in thousandths, or ppt) we'll charge for funds routed through a leased channel. Note: 1ppt = 1,000ppm

# exposesecret-passphrase <arg>                   Enable exposesecret command to allow HSM Secret backup, with this passphrase
# disable-mpp                                     Disable multi-part payments.
# fetchinvoice-noconnect                          Don't try to connect directly to fetch/pay an invoice.

# renepay-debug-mcf                               Enable renepay MCF debug info.
# renepay-debug-payflow                           Enable renepay payment flows debug info.

# xpay-handle-pay <arg>                           Make xpay take over pay commands it can handle. (default: false)

# bookkeeper-dir <arg>                            Location for bookkeeper records.
# bookkeeper-db <arg>                             Location of the bookkeeper database

# grpc-host <arg>                                 Which host should the grpc listen for incomming connections? (default: 127.0.0.1)
# grpc-msg-buffer-size <arg>                      Number of notifications which can be stored in the grpc message buffer. Notifications can be skipped if this buffer is full (default: 1024)
# grpc-port <arg>                                 Which port should the grpc plugin listen for incoming connections? (default: 9736)

# wss-bind-addr <arg>                             WSS proxy address to connect with WS
# wss-certs <arg>                                 Certificate location for WSS proxy (default: /home/satoshi/.lightning/bitcoin)

# clnrest-certs <arg>                             Path for certificates (for https) (default: /home/satoshi/.lightning/bitcoin)
# clnrest-protocol <arg>                          REST server protocol (default: https)
# clnrest-host <arg>                              REST server host (default: 127.0.0.1)
# clnrest-port <arg>                              REST server port to listen
# clnrest-cors-origins <arg>                      Cross origin resource sharing origins (default: *)
# clnrest-csp <arg>                               Content security policy (CSP) for the server (default: default-src 'self'; font-src 'self'; img-src 'self' data:; frame-src 'self'; sty...)
# clnrest-swagger-root <arg>                      Root path for Swagger UI (default: /)

# plugin-dir <arg>                                Add a directory to AUTOMATICALLY load plugins from (can be used multiple times) (default: /path/to/your/.lightning/plugins)
# plugin <arg>                                    Add a plugin to be run (can be used multiple times)
# important-plugin <arg>                          Add an important plugin to be run (can be used multiple times). Die if the plugin dies

EOF
sudo chown root:lightning /etc/lightningd.conf
sudo chmod 640 /etc/lightningd.conf

# Create lightning & bitcoin directory
sudo mkdir -p /var/lib/lightningd
sudo chown root:lightning -R /var/lib/lightningd
sudo chmod 670 -R /var/lib/lightningd
sudo mkdir /var/lib/bitcoin
sudo touch /var/lib/bitcoin/bitcoin.conf # Required for bitcoin-cli utility to function

# Create lightningd log file location /w appropriate permissions
sudo mkdir -p /var/log/lightningd
sudo chown root:lightning -R /var/log/lightningd
sudo chmod 670 -R /var/log/lightningd

# Configure lightningd's Log file from Filling up the partition ???????????????????????????killall???????????????
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

# Reload/Enable System Control for new processes
sudo systemctl daemon-reload
sudo systemctl enable btc-node-autossh
sudo systemctl enable lightningd






##2024-12-16T18:15:53.221Z UNUSUAL plugin-bookkeeper: topic 'utxo_deposit' is not a known notification topic
##2024-12-16T18:15:53.221Z UNUSUAL plugin-bookkeeper: topic 'utxo_spend' is not a known notification topic
###plugin-bookkeeper: Setting up database at sqlite3://accounts.sqlite3
############# it was located in /var/lib/lightningd/bitcoin/accounts.sqlite3 ?????????


##2024-12-16T18:15:53.221Z DEBUG   lightningd: io_break: check_plugins_manifests
##2024-12-16T18:15:53.222Z DEBUG   lightningd: io_loop_with_timers: plugins_init

2024-12-17T11:04:02.767Z DEBUG   lightningd: io_break: connect_init_done
2024-12-17T11:04:02.767Z DEBUG   lightningd: io_loop: connectd_init


2024-12-17T11:11:26.705Z DEBUG   plugin-manager: started(779) /usr/local/libexec/c-lightning/plugins/autoclean
2024-12-17T11:11:26.706Z DEBUG   plugin-manager: started(780) /usr/local/libexec/c-lightning/plugins/chanbackup
2024-12-17T11:11:26.707Z DEBUG   plugin-manager: started(781) /usr/local/libexec/c-lightning/plugins/bcli
2024-12-17T11:11:26.709Z DEBUG   plugin-manager: started(782) /usr/local/libexec/c-lightning/plugins/commando
2024-12-17T11:11:26.710Z DEBUG   plugin-manager: started(783) /usr/local/libexec/c-lightning/plugins/funder
2024-12-17T11:11:26.711Z DEBUG   plugin-manager: started(784) /usr/local/libexec/c-lightning/plugins/topology
2024-12-17T11:11:26.712Z DEBUG   plugin-manager: started(785) /usr/local/libexec/c-lightning/plugins/exposesecret
2024-12-17T11:11:26.714Z DEBUG   plugin-manager: started(786) /usr/local/libexec/c-lightning/plugins/keysend
2024-12-17T11:11:26.715Z DEBUG   plugin-manager: started(787) /usr/local/libexec/c-lightning/plugins/offers
2024-12-17T11:11:26.716Z DEBUG   plugin-manager: started(788) /usr/local/libexec/c-lightning/plugins/pay
2024-12-17T11:11:26.717Z DEBUG   plugin-manager: started(789) /usr/local/libexec/c-lightning/plugins/recklessrpc
2024-12-17T11:11:26.718Z DEBUG   plugin-manager: started(790) /usr/local/libexec/c-lightning/plugins/recover
2024-12-17T11:11:26.720Z DEBUG   plugin-manager: started(791) /usr/local/libexec/c-lightning/plugins/txprepare
2024-12-17T11:11:26.721Z DEBUG   plugin-manager: started(792) /usr/local/libexec/c-lightning/plugins/cln-renepay
2024-12-17T11:11:26.722Z DEBUG   plugin-manager: started(793) /usr/local/libexec/c-lightning/plugins/cln-xpay
2024-12-17T11:11:26.723Z DEBUG   plugin-manager: started(794) /usr/local/libexec/c-lightning/plugins/spenderp
2024-12-17T11:11:26.724Z DEBUG   plugin-manager: started(795) /usr/local/libexec/c-lightning/plugins/cln-askrene
2024-12-17T11:11:26.725Z DEBUG   plugin-manager: started(796) /usr/local/libexec/c-lightning/plugins/sql
2024-12-17T11:11:26.727Z DEBUG   plugin-manager: started(797) /usr/local/libexec/c-lightning/plugins/cln-grpc
2024-12-17T11:11:26.728Z DEBUG   plugin-manager: started(798) /usr/local/libexec/c-lightning/plugins/bookkeeper
2024-12-17T11:11:26.729Z DEBUG   plugin-manager: started(800) /usr/local/libexec/c-lightning/plugins/clnrest/clnrest
2024-12-17T11:11:26.730Z DEBUG   plugin-manager: started(801) /usr/local/libexec/c-lightning/plugins/wss-proxy/wss-proxy




########## If someone opens a channel with me, I want them to carry at least a little of the burden
      ####### Avoid openining a ton of small channels, sending the sats and then leaving them for me to close with large fees.
      ####### Well, we don't have access to that money. How to get the whole amount if they have gone dorminant without the

# According to the BOLT 3 specification, the peer that funded the channel will incur the costs of closing fees.
# It also seems that these fees would be calculated before closing a payment channel.
# Both parties already have a transaction with a built in fee that can be used to close the channel that they can broadcast at anytime.
###### Then, the only policiy is that of being able to demand the reserved fee amount for someone to be able to open a channel with me.






























# Generating Strong Wallet Passphrase
STRONGPASSPF=$(openssl rand -base64 24)
STRONGPASSPF=${STRONGPASSPF//\//0} # Replace '/' characters with '0'
STRONGPASSPF=${STRONGPASSPF//+/1} # Replace '+' characters with '1'
STRONGPASSPF=${STRONGPASSPF//=/} # Replace '=' characters with ''
STRONGPASSPF=${STRONGPASSPF//O/0} # Replace 'O' (o) characters with '0'
STRONGPASSPF=${STRONGPASSPF//l/1} # Replace 'l' (L) characters with '1'
echo $STRONGPASSPF | sudo tee /root/passphrase
sudo chmod 400 /root/passphrase



# Restart the machine
sudo reboot now

