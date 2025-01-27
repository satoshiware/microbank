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

This lightning node requires access to a Bitcoin full node connected via a Secure SSH Tunnel
    Before this connection will work, add the ssh key (sudo cat /root/.ssh/btc-node-autossh-key.pub)
    to the Bitcoin Full Node (sudo nano /home/btc-remote-cli/.ssh/authorized_keys)

Files:
    /etc/lightningd.conf # Core Lightningd Configureation File
    /var/lib/lightningd" # Lightningd Var Directory
    /var/lib/bitcoin/bitcoin.conf # Bitcoin directory w/ bitcoin.conf file; both required for bitcoin-cli utility to run
    /root/.ssh/known_hosts # Contains the Bitcoin full node host key

Log:
    sudo cat /var/log/lightningd/log

Info' Commands:
    sudo systemctl status btc-node-autossh # Show the SSH Tunnel to the Bitcoin Full Node status
    sudo systemctl status lightningd # Show the status of the lightning daemon
    sudo journalctl -a -u lightningd # Show system log for lightningd
    sudo journalctl -f -a -u lightningd # Show ROLLING system log for lightningd

Network:
    Using ipv4 address only to announce gossip informatioon. The lightningd's port is 9735.
    REMEMBER to setup forwarding on your NAT firewall to this internal port 9735.
        The lightningd.conf has the internal port and external port configured the same (i.e. 9735) by default.
        If you need a different external port forwarded internally, be sure to update the external port denoted
        by the "announce-addr" parameter in /etc/lightningd.conf and restart the node.

Global Liquidity:
    Create unsolicited one-way channels (no leased funds; we're the only funder) to well-connected nodes
    Select nodes that can EASILY help with inbound liquidity (e.g. wallet, exchange nodes, etc.)
    Start with a few channels and add more as needed (avoid adding channels if preexisting ones are underutilized)
    The minimum amount required to establish a channel is different for each node.
    NOTE: THIS NODE REQUIRES 1 MILLION $ATS FOR INCOMING CHANNELS!
    When establishing these channels, will use all the defaults except for the reserve requirement (it'll be 0).

    Channel Balancig via Dynamic Fee Management: In order to maintain the best global liquidity / connectivity,
    the fees are only a hair above zero; however, as more channels are established with significant daily throughput,
    it may be wise to employ some plugin (in the future) to dynamically adjust the "fee-per-satoshi" on specific
    "global" channels to encourage the use of other "global" channels. NOTE: FEES ONLY APPLY TO PAYMENTS ROUTED IN (NOT OUT).

    Here are some potential nodes that consisit of well-know bitcoin services, Lightning Wallets, reliable exchanges, etc. (last update: 12/21/2024):
        03c8e5f583585cac1de2b7503a6ccd3c12ba477cfd139cd4905be504c2f48e86bd  # Strike
        02f1a8c87607f415c8f22c00593002775941dea48869ce23096af27b0cfdcc0b69  # Kraken
        035e4ff418fc8b5554c5d9eea66396c227bd429a3251c8cbc711002ba215bfc226  # Wallet of Satoshi
        03037dc08e9ac63b82581f79b662a4d0ceca8a8ca162b1af3551595b8f2d97b70a  # River Financial #1
        03aab7e9327716ee946b8fbfae039b0db85356549e72c5cca113ea67893d0821e5  # River Financial #2
        033d8656219478701227199cbd6f670335c8d408a92ae88b962c49d4dc0e83e025  # Bitfinex #1
        03cde60a6323f7122d5178255766e38114b4722ede08f7c9e0c5df9b912cc201d6  # Bitfinex #2
        02535215135eb832df0f9858ff775bd4ae0b8911c59e2828ff7d03b535b333e149  # Binance #1
        02b2ae15001601b74eee8ddbd036315c5fbd415b24f88f24d5266820169dfd13de  # Binance #2
        037659a0ac8eb3b8d0a720114efc861d3a940382dcfa1403746b4f8f6b2e8810ba  # Nicehash #1
        02542b74385b4965bf6b5616a0eaafee06b58ac62e3d441fdb2380a92ded3cf124  # Nicehash #2
        0294ac3e099def03c12a37e30fe5364b1223fd60069869142ef96580c8439c2e0a  # okx
        030c3f19d742ca294a55c00376b3b355c3c90d61c6b6b39554dbc7ac19b141c14f  # Bitrefill
        03864ef025fde8fb587d989186ce6a4a186895ee44a926bfc370e2c366597a3f8f  # ACINQ (Eclair Implementation)
        039174f846626c6053ba80f5443d0db33da384f1dde135bf7080ba1eec465019c3  # Lightspark (Coinbase) #1
        02a98e8c590a1b5602049d6b21d8f4c8861970aa310762f42eae1b2be88372e924  # Lightspark (Coinbase) #2
        02d0e03736cbfc73f3c005bc3770327df0e84bd69bc8e557c279887344deb8bce2  # Blockstream (PeerSwap)
        02df5ffe895c778e10f7742a6c5b8a0cefbe9465df58b92fadeb883752c8107c8f  # Blockstream (Store)

Local (Trusted) Channels:
    Channels created between TRUSTED "banking" peers are treated differently. The fees are always kept a hair above zero
    and both parties create channels (of equal size), with the default "feerate", that are meant to be open indefinitely
    with zero reserve. This is a demonstration of long-term relationship commitment. NOTE: THIS NODE REQUIRES 1 MILLION
    $ATS FOR INCOMING CHANNELS! (This would be a good candidate for "Dual Funded V2 Channels", but we opted for the
    simple single funder [for now]). Additional channels are opened (and/or closed) by either party as needed. To
    maintain balanced channels beyond well-known strategies in the lightning network, either "bank" can just leverage
    the tools offered by the other.
	
Incoming (Unsolicited) Channels:
    Someone's using our node to bootstrap themselves into the lightning network. How flattering! NOTE: THIS NODE
    REQUIRES 1 MILLION $ATS FOR INCOMING CHANNELS! The management or maintenance of these channels (e.g. balancing) is
    left to the funders (aka the creators). CORE LIGHTNING FEATURE REQUEST: Require a set amount to be pushed to this
    node (i.e. donated) when opening a channel to cover any potential loss from paying fees for extra utxos and/or any
    satoshis lost to fees because of dust limits.

    If a channel becomes unresponsive for more than 14 days or if the fees (or other settings) become too unreasonable,
	then the operator may close all channels with that peer! Fees should be increased from their default (near zero)
	values on these incoming channels. When setting or changing a fee, consider making changes gradually, consider the 
	peer's fees on the given channel, consider the fees on the peer's other (competing) channels, and consider our
	node's liquidity needs both incoming and outgoing.

    Note: These "policies" are not enforced in code (yet), they are executed manually.

Hosted Channels !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
	Let's create another node that will offer all the lightning channels for the "self-custody" lightning wallet.
	The connection between this node and the "hosted channels" node will in of itself also be hosted. This single
	channel connection will be where we control all the fees. All the individual channels will be freeish.
	What if they want to deposit via On-Chain Payment??? how does that work? Create an invoice that also has ...
	needs development for sure. 
		One will be assigned at random and they can get a better customized one via purchasing!!! how so???
		If they want an lightning address, they will have to go get one. 
	

	
min-emergency-msat=100000000




	Create lightning Invoices (and on-chain over a certain amount to the Bitcoin Wallet)
	Static Invoices that can be paid multiple time.
	***** HOW TO PUSH NOTIFICATIONS OF PAYMENTS ******		
	

	waitanyinvoice
	waitinvoice
	signinvoice
	sendinvoice
	preapproveinvoice
	listinvoices - Gets status of a specific invoice, if it exists, or the status of all invoices.
	Listinvoicerequests
	invoicerequest
	invoice - Creates the expectation of a payment of a given amount.
	fetchinvoice 
	disableinvoice request
	delinvoice
	createinvoice - signs and saves an invoice into the database
	
	offer
	listoffers
	disableoffer (if it doesn't expire automatically)
	
	



*** Send payments to an invoice (xpay)
	Static, natural, lightning address, what about an on-chain payment?? That's the BTC Wallet??







	
	Lightning Address (Can this handle on chain as well??? Curious)
	
	WatchTower for others and find others for me! 

**** BTCPAY ******
	****INCLUDE ONCHAIN PAYMENTS ******


**** BACKUP/RESTORE


EOF
read -p "Press the enter key to continue..."

# Run latest updates and upgrades
sudo apt-get -y update
sudo DEBIAN_FRONTEND=noninteractive apt-get -y install --only-upgrade openssh-server # Upgrade seperatly to ensure non-interactive mode
sudo apt-get -y upgrade

# Install Packages
sudo apt-get -y install wget psmisc xz-utils libpq5 autossh jq

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

# Query freely available services to discover or get the external IPv4 address
if [[ 0 = 1 ]]; then MY_EXTERNAL_IP=127.0.0.1
elif [[ $(curl -s -4 icanhazip.com) =~ ^(([1-9]?[0-9]|1[0-9][0-9]|2([0-4][0-9]|5[0-5]))\.){3}([1-9]?[0-9]|1[0-9][0-9]|2([0-4][0-9]|5[0-5]))$ ]]; then MY_EXTERNAL_IP=$(curl -s -4 icanhazip.com)
elif [[ $(curl -s -4 http://dynamicdns.park-your-domain.com/getip) =~ ^(([1-9]?[0-9]|1[0-9][0-9]|2([0-4][0-9]|5[0-5]))\.){3}([1-9]?[0-9]|1[0-9][0-9]|2([0-4][0-9]|5[0-5]))$ ]]; then MY_EXTERNAL_IP=$(curl -s -4 http://dynamicdns.park-your-domain.com/getip)
elif [[ $(curl -s -4 ifconfig.me) =~ ^(([1-9]?[0-9]|1[0-9][0-9]|2([0-4][0-9]|5[0-5]))\.){3}([1-9]?[0-9]|1[0-9][0-9]|2([0-4][0-9]|5[0-5]))$ ]]; then MY_EXTERNAL_IP=$(curl -s -4 ifconfig.me)
elif [[ $(curl -s -4 ipinfo.io/ip) =~ ^(([1-9]?[0-9]|1[0-9][0-9]|2([0-4][0-9]|5[0-5]))\.){3}([1-9]?[0-9]|1[0-9][0-9]|2([0-4][0-9]|5[0-5]))$ ]]; then MY_EXTERNAL_IP=$(curl -s -4 ipinfo.io/ip)
elif [[ $(curl -s -4 api.ipify.org) =~ ^(([1-9]?[0-9]|1[0-9][0-9]|2([0-4][0-9]|5[0-5]))\.){3}([1-9]?[0-9]|1[0-9][0-9]|2([0-4][0-9]|5[0-5]))$ ]]; then MY_EXTERNAL_IP=$(curl -s -4 api.ipify.org)
elif [[ $(curl -s -4 ident.me) =~ ^(([1-9]?[0-9]|1[0-9][0-9]|2([0-4][0-9]|5[0-5]))\.){3}([1-9]?[0-9]|1[0-9][0-9]|2([0-4][0-9]|5[0-5]))$ ]]; then MY_EXTERNAL_IP=$(curl -s -4 ident.me)
elif [[ $(curl -s -4 checkip.amazonaws.com) =~ ^(([1-9]?[0-9]|1[0-9][0-9]|2([0-4][0-9]|5[0-5]))\.){3}([1-9]?[0-9]|1[0-9][0-9]|2([0-4][0-9]|5[0-5]))$ ]]; then MY_EXTERNAL_IP=$(curl -s -4 checkip.amazonaws.com)
elif [[ $(curl -s -4 ipecho.net/plain) =~ ^(([1-9]?[0-9]|1[0-9][0-9]|2([0-4][0-9]|5[0-5]))\.){3}([1-9]?[0-9]|1[0-9][0-9]|2([0-4][0-9]|5[0-5]))$ ]]; then MY_EXTERNAL_IP=$(curl -s -4 ipecho.net/plain)
elif [[ $(curl -s -4 ifconfig.co) =~ ^(([1-9]?[0-9]|1[0-9][0-9]|2([0-4][0-9]|5[0-5]))\.){3}([1-9]?[0-9]|1[0-9][0-9]|2([0-4][0-9]|5[0-5]))$ ]]; then MY_EXTERNAL_IP=$(curl -s -4 ifconfig.co)
else MY_EXTERNAL_IP=127.0.0.1; fi

# Generate Core Lightning Configuration File with the Appropriate Permissions ????????????????????????????????????????????????????????????????????????????????????
cat << EOF | sudo tee /etc/lightningd.conf
# Select the network
network=bitcoin
# Run in the background
daemon
# Set base directory
lightning-dir=/var/lib/lightningd
# Amount to leave in wallet for spending anchor closes (default: 25000000)
min-emergency-msat=100000000

############## LND Node Configuration ##############
# RRGGBB hex color for node
rgb=$LIGHTNING_RGBHEX_COLOR
# Up to 32-byte alias for node
alias=${MICRO_BANK_NAME// /}

############## Bitcoin Node ##############
# datadir arg for bitcoin-cli
bitcoin-datadir=/var/lib/bitcoin
# bitcoind RPC username
bitcoin-rpcuser=satoshi
# bitcoind RPC password
bitcoin-rpcpassword=satoshi
# bitcoind RPC host to connect to
bitcoin-rpcconnect=$BTC_NODE_LOCAL

############## Logging ##############
# log level (io, debug, info, unusual, broken) [:prefix] (default: info)
log-level=debug
# Log to file (- for stdout)
log-file=/var/log/lightningd/log

############## Channel Creation Policy ##############
# Minimum capacity in satoshis for accepting channels (default: 10000)
min-capacity-sat=1000000
# Minimum fee to charge for every (incomming) payment which passes through (in HTLC) (millisatoshis; 1/1000 of a satoshi) (default: 1000)
fee-base=1
# Microsatoshi fee for every satoshi in HTLC (10 is 0.001%, 100 is 0.01%, 1000 is 0.1% etc.) (default: 10)
fee-per-satoshi=1

############## Network ##############
# Set an IP address and port to listen on
bind-addr=0.0.0.0:9735
# Set an IP address and port to announce so peers can find your node
announce-addr=${MY_EXTERNAL_IP}:9735





# subdaemon <arg>                                 Arg specified as SUBDAEMON:PATH. Specifies an alternate subdaemon binary. If the supplied path is relative the subdaemon binary is found in the working directory. This option may be specified multiple times. For example, --subdaemon=hsmd:remote_signer would use a hypothetical remote signing subdaemon.
# invoices-onchain-fallback                       Include an onchain address in invoices and mark them as paid if payment is received on-chain

# encrypted-hsm                                   Set the password to encrypt hsm_secret with. If no password is passed through command line, you will be prompted to enter it on startup
# exposesecret-passphrase <arg>                   Enable exposesecret command to allow HSM Secret backup, with this passphrase
# fetchinvoice-noconnect                          Don't try to connect directly to fetch/pay an invoice.

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
sudo chmod 610 -R /var/lib/lightningd
sudo mkdir /var/lib/bitcoin
sudo touch /var/lib/bitcoin/bitcoin.conf # Required for bitcoin-cli utility to function

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

# Reload/Enable System Control for new processes
sudo systemctl daemon-reload
sudo systemctl enable btc-node-autossh
sudo systemctl enable lightningd


















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

