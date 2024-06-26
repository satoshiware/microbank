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
This readme was generated by the "bitcoin_node.sh" install script.
The "bitcoin_node.sh" script installs a bitcoin node readied to receive connections from external services.
To run this script, you'll need the Bitcoin Core download URL (tar.gz file) with its SHA 256 Checksum to continue.
Also, you will need to plug in a USB drive that will be used to backup the "bank" wallet along with the "passphrase"
    STORE IN SAFE & SECURE PLACE WHEN FINISHED!!!
To execute this script, login as a sudo user (that is not root) and execute the following commands:
    sudo apt-get -y install git
    cd ~; git clone https://github.com/satoshiware/microbank
    bash ./microbank/scripts/bitcoin_node.sh
    rm -rf microbank

FYI:
    Use the bitnode utility to see & manage blockchain, wallet, mempool, and mining information as well as make & bump TXs (including importing and loading Satoshi Coins) etc.

    The "$USER/.ssh/authorized_keys" file contains administrator login keys.
    The "ext_rpc/.ssh/authorized_keys" file contains login keys for external services (lightning, electurm, stratum, and btcpay servers).

    The "/var/lib/bitcoin" directory contains debug logs, blockchain, etc.
    The bitcoind's log files can be view with this file: "/var/log/bitcoin/debug.log" (links to /var/lib/bitcoin/debug.log)
    The "/var/lib/bitcoin/wallets" directory contains the various wallet directories.

    Passwords: /root/extrpcpasswd (External; user=ext_rpc), /root/lclrpcpasswd (Localhost; user=local_rpc), /root/strrpcpasswd (Stratum; user=stratum_rpc), and /root/passphrase (Wallet Passphrase)
    External RPC Ports: localhost:8332 (Bitcoin RPC), localhost:8433 (Bitcoin ZMQ)

    Bitcoin configuratijon: /etc/bitcoin.conf

    The "sudo systemctl status bitcoind" command show the status of the bitcoin daemon.

Hardware:
    Rasperry Pi Compute Module 4: CM4008000 (w/ Compute Blade)
    8GB RAM
    M.2 PCI SSD 2TB
    Netgear 5 Port Switch (PoE+ @ 120W)
EOF
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

# Install rpcauth Utility
sudo mkdir -p /usr/share/python
sudo mv ~/microbank/python/rpcauth.py /usr/share/python/rpcauth.py
sudo chmod +x /usr/share/python/rpcauth.py
echo "#"\!"/bin/sh" | sudo tee /usr/share/python/rpcauth.sh
echo "python3 /usr/share/python/rpcauth.py \$1 \$2" | sudo tee -a /usr/share/python/rpcauth.sh
sudo ln -s /usr/share/python/rpcauth.sh /usr/bin/rpcauth
sudo chmod 755 /usr/bin/rpcauth

# Download Bitcoin Core, Verify Checksum
read -p "Bitcoin Core URL (.tar.gz): " SOURCE
read -p "SHA 256 Checksum for the .tar.gz source file: " CHECKSUM

wget $SOURCE
if ! [ -f ~/${SOURCE##*/} ]; then echo "Error: Could not download source!"; exit 1; fi
if [[ ! "$(sha256sum ~/${SOURCE##*/})" == *"$CHECKSUM"* ]]; then
    echo "Error: SHA 256 Checksum for file \"~/${SOURCE##*/}\" was not what was expected!"
    exit 1
fi
tar -xzf ${SOURCE##*/}
rm ${SOURCE##*/}

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

#Create a bitcoin System User
sudo useradd --system --shell=/sbin/nologin bitcoin

# Wrap the Bitcoin CLI Binary with its Runtime Configuration
echo "alias btc=\"sudo -u bitcoin /usr/bin/bitcoin-cli -datadir=/var/lib/bitcoin -conf=/etc/bitcoin.conf\"" | sudo tee -a /etc/bash.bashrc # Reestablish alias @ boot

# Generate Strong Bitcoin RPC Passwords. Replace '/' characters with '0', Replace '+' characters with '1', and Replace '=' characters with ''
EXTRPCPASSWD=$(openssl rand -base64 16); EXTRPCPASSWD=${EXTRPCPASSWD//\//0}; EXTRPCPASSWD=${EXTRPCPASSWD//+/1}; EXTRPCPASSWD=${EXTRPCPASSWD//=/} # External RPC
LCLRPCPASSWD=$(openssl rand -base64 16); LCLRPCPASSWD=${LCLRPCPASSWD//\//0}; LCLRPCPASSWD=${LCLRPCPASSWD//+/1}; LCLRPCPASSWD=${LCLRPCPASSWD//=/} # Localhost RPC
echo $EXTRPCPASSWD | sudo tee /root/extrpcpasswd
echo $LCLRPCPASSWD | sudo tee /root/lclrpcpasswd
sudo chmod 400 /root/extrpcpasswd
sudo chmod 400 /root/lclrpcpasswd

# Generate Bitcoin Configuration File with the Appropriate Permissions
cat << EOF | sudo tee /etc/bitcoin.conf
# [core]
# Maintain a full transaction index, used by the getrawtransaction rpc call.
txindex=1

# [rpc]
# Accept command line and JSON-RPC commands.
server=1

# Accept public REST requests.
rest=1

# Username and hashed password for JSON-RPC connections. The field <userpw> comes in the format: <USERNAME>:<SALT>$<HASH>. RPC clients connect using
$(rpcauth ext_rpc $(sudo cat /root/extrpcpasswd) | grep 'rpcauth')
$(rpcauth local_rpc $(sudo cat /root/lclrpcpasswd) | grep 'rpcauth')

# White List Blockchain RPCs
rpcwhitelist=ext_rpc:getbestblockhash,getblock,getblockchaininfo,getblockcount,getblockfilter,getblockhash,getblockheader,getblockstats,getchaintips,getchaintxstats,getdifficulty,getmempoolancestors,getmempooldescendants,getmempoolentry,getmempoolinfo,getrawmempool,gettxout,gettxoutproof,gettxoutsetinfo,preciousblock,pruneblockchain,savemempool,scantxoutset,verifychain,verifytxoutproof
# White List Control RPCs
rpcwhitelist=ext_rpc:getmemoryinfo,getrpcinfo,help,logging,stop,uptime
# White List Generating RPCs
rpcwhitelist=ext_rpc:generateblock,generatetoaddress,generatetodescriptor
# White List Mining RPCs
rpcwhitelist=ext_rpc:getblocktemplate,getmininginfo,getnetworkhashps,prioritisetransaction,submitblock,submitheader
# White List Network RPCs
#rpcwhitelist=ext_rpc:addnode,clearbanned,disconnectnode,getaddednodeinfo,getconnectioncount,getnettotals,getnetworkinfo,getnodeaddresses,getpeerinfo,listbanned,ping,setban,setnetworkactive
# White List Rawtransactions RPCs
rpcwhitelist=ext_rpc:analyzepsbt,combinepsbt,combinerawtransaction,converttopsbt,createpsbt,createrawtransaction,decodepsbt,decoderawtransaction,decodescript,finalizepsbt,fundrawtransaction,getrawtransaction,joinpsbts,sendrawtransaction,signrawtransactionwithkey,testmempoolaccept,utxoupdatepsbt
# White List Util RPCs
rpcwhitelist=ext_rpc:createmultisig,deriveaddresses,estimatesmartfee,getdescriptorinfo,getindexinfo,signmessagewithprivkey,validateaddress,verifymessage
# White List Wallet RPCs
#rpcwhitelist=ext_rpc:abandontransaction,abortrescan,addmultisigaddress,backupwallet,bumpfee,createwallet,dumpprivkey,dumpwallet,encryptwallet,getaddressesbylabel,getaddressinfo,getbalance,getbalances,getnewaddress,getrawchangeaddress,getreceivedbyaddress,getreceivedbylabel,gettransaction,getunconfirmedbalance,getwalletinfo,importaddress,importdescriptors,importmulti,importprivkey,importprunedfunds,importpubkey,importwallet,keypoolrefill,listaddressgroupings,listlabels,listlockunspent,listreceivedbyaddress,listreceivedbylabel,listsinceblock,listtransactions,listunspent,listwalletdir,listwallets,loadwallet,lockunspent,psbtbumpfee,removeprunedfunds,rescanblockchain,send,sendmany,sendtoaddress,sethdseed,setlabel,settxfee,setwalletflag,signmessage,signrawtransactionwithwallet,unloadwallet,upgradewallet,walletcreatefundedpsbt,walletlock,walletpassphrase,walletpassphrasechange,walletprocesspsbt

# Set the number of threads to service RPC calls (default = 4)
rpcthreads=16

# [zeromq]
# Enable publishing of block hashes to <address>.
zmqpubhashblock=127.0.0.1:8433
# Enable publishing of transaction hashes to <address>.
zmqpubhashtx=127.0.0.1:8433
# Enable publishing of raw block hex to <address>.
zmqpubrawblock=127.0.0.1:8433
# Enable publishing of raw transaction hex to <address>.
zmqpubrawtx=127.0.0.1:8433
# Enable publish hash block and tx sequence in <address>.
zmqpubsequence=127.0.0.1:8433
EOF
sudo chown root:bitcoin /etc/bitcoin.conf
sudo chmod 640 /etc/bitcoin.conf

# Configure bitcoind's Log Files; Prevents them from Filling up the Partition
cat << EOF | sudo tee /etc/logrotate.d/bitcoin
/var/lib/bitcoin/debug.log {
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
sudo ufw allow 8333 # Open port for p2p Bitcoin mainnet
sudo ufw --force enable # Enable Firewall @ Boot and Start it now!

# Install/Setup/Enable SSH(D)
sudo sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config # Disable password login
sudo sed -i 's/X11Forwarding yes/#X11Forwarding no/g' /etc/ssh/sshd_config # Disable X11Forwarding (default value)
sudo sed -i 's/#AllowTcpForwarding yes/AllowTcpForwarding Local/g' /etc/ssh/sshd_config # Only allow local port forwarding
sudo sed -i 's/#.*StrictHostKeyChecking ask/\ \ \ \ StrictHostKeyChecking yes/g' /etc/ssh/ssh_config # Enable strict host verification

echo -e "\nMatch User *,"'!'"ext_rpc,"'!'"root,"'!'"$USER" | sudo tee -a /etc/ssh/sshd_config
echo -e "\tAllowTCPForwarding no" | sudo tee -a /etc/ssh/sshd_config
echo -e "\tPermitTTY no" | sudo tee -a /etc/ssh/sshd_config
echo -e "\tForceCommand /usr/sbin/nologin" | sudo tee -a /etc/ssh/sshd_config

echo -e "\nMatch User ext_rpc" | sudo tee -a /etc/ssh/sshd_config
echo -e "\tPermitTTY no" | sudo tee -a /etc/ssh/sshd_config
echo -e "\tPermitOpen localhost:8332 localhost:8433" | sudo tee -a /etc/ssh/sshd_config # Denies any request of local forwarding besides localhost:8332 (Bitcoin RPC), and localhost:8433 (Bitcoin ZMQ)

# Setup a "no login" users called "ext_rpc"
sudo useradd -s /bin/false -m -d /home/ext_rpc ext_rpc

# Create .ssh folder (ext_rpc); Set ownership and permissions
sudo mkdir -p /home/ext_rpc/.ssh
sudo touch /home/ext_rpc/.ssh/authorized_keys
sudo chown -R ext_rpc:ext_rpc /home/ext_rpc/.ssh
sudo chmod 700 /home/ext_rpc/.ssh
sudo chmod 600 /home/ext_rpc/.ssh/authorized_keys

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
sudo systemctl enable ssh
sudo systemctl enable bitcoind --now
echo "waiting a few seconds for bitcoind to start"; sleep 15

# Generate "bank" Wallet
sudo -u bitcoin /usr/bin/bitcoin-cli -datadir=/var/lib/bitcoin -conf=/etc/bitcoin.conf --named createwallet wallet_name="bank" passphrase=$(sudo cat /root/passphrase) load_on_startup=true

# Backup Wallets
sudo mkdir -p /media/usb
sudo mount /dev/sda1 /media/usb
sudo install -C -m 400 /var/lib/bitcoin/wallets/bank/wallet.dat /media/usb/bank.dat
sudo install -C -m 400 /root/passphrase /media/usb/passphrase
sudo umount /dev/sda1
sudo rm -rf /media/usb

# Create Aliases to lock and unlocks (24 Hours) wallets
echo "alias unlockwallets=\"btc -rpcwallet=bank walletpassphrase \\\$(sudo cat /root/passphrase) 86400\"" | sudo tee -a /etc/bash.bashrc
echo "alias lockwallets=\"btc -rpcwallet=bank walletlock\"" | sudo tee -a /etc/bash.bashrc

# Install the "bitnode" utility (bitnode.sh)
bash ~/microbank/scripts/bitnode.sh -i

# Restart the machine
sudo reboot now