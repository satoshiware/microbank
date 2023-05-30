#!/bin/bash

echo "Make sure to shutdown all other Bitcoin Core (micro) instances on this Windows machine."
echo "Port collisions will interrupt this script."; read -p "Press any key to continue ..."

# Run latest updates and upgrades
sudo apt-get -y update
sudo apt-get -y upgrade

# Install Packages
sudo apt-get -y install wget psmisc autossh ssh ufw build-essential yasm autoconf automake libtool libzmq3-dev python git

# Install rpcauth Utility
sudo wget https://github.com/satoshiware/bitcoin/releases/download/v23001/rpcauth.py -P /usr/share/python
if [[ ! "$(sha256sum /usr/share/python/rpcauth.py)" == *"b0920f6d96f8c72cee49df90ee4d0bf826bbe845596ecc056c6bc0873c146d1f"* ]]; then
        echo "Error: sha256sum for file \"/usr/share/python/rpcauth.py\" was not what was expected!"
        exit 1
fi
sudo chmod +x /usr/share/python/rpcauth.py
echo "#"\!"/bin/sh" | sudo tee /usr/share/python/rpcauth.sh
echo "python3 /usr/share/python/rpcauth.py \$1 \$2" | sudo tee -a /usr/share/python/rpcauth.sh
sudo ln -s /usr/share/python/rpcauth.sh /usr/bin/rpcauth
sudo chmod 755 /usr/bin/rpcauth

# Download Bitcoin Core (micro), Verify Checksum
cd ~; wget https://github.com/satoshiware/bitcoin/releases/download/v23001/bitcoin-x86_64-linux-gnu.tar.gz
if [[ ! "$(sha256sum ~/bitcoin-x86_64-linux-gnu.tar.gz)" == *"d868e59d59e338d5dedd25e9093c9812a764b6c6dc438871caacf8e692a9e04d"* ]]; then
        echo "Error: sha256sum for file \"bitcoin-x86_64-linux-gnu.tar.gz\" was not what was expected!"
        exit 1
fi

# Install Binaries
tar -xzf bitcoin-x86_64-linux-gnu.tar.gz
sudo install -m 0755 -o root -g root -t /usr/bin bitcoin-install/bin/*
rm bitcoin-x86_64-linux-gnu.tar.gz
rm -rf bitcoin-install

# Prepare Service Configuration
cat << EOF | sudo tee /etc/systemd/system/bitcoind.service
[Unit]
Description=Bitcoin daemon
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/bin/bitcoind -micro -daemonwait -pid=/run/bitcoin/bitcoind.pid -conf=/etc/bitcoin.conf -datadir=/var/lib/bitcoin
ExecStop=/usr/bin/bitcoin-cli -micro -conf=/etc/bitcoin.conf -datadir=/var/lib/bitcoin stop

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
echo "alias btc=\"sudo -u bitcoin /usr/bin/bitcoin-cli -micro -datadir=/var/lib/bitcoin -conf=/etc/bitcoin.conf\"" | sudo tee -a /etc/bash.bashrc # Reestablish alias @ boot

# Generate Strong Bitcoin RPC Password
BTCRPCPASSWD=$(openssl rand -base64 16)
BTCRPCPASSWD=${BTCRPCPASSWD//\//0} # Replace '/' characters with '0'
BTCRPCPASSWD=${BTCRPCPASSWD//+/1} # Replace '+' characters with '1'
BTCRPCPASSWD=${BTCRPCPASSWD//=/} # Replace '=' characters with ''
echo $BTCRPCPASSWD | sudo tee /root/rpcpasswd
BTCRPCPASSWD="" # Erase from memory
sudo chmod 400 /root/rpcpasswd

# Generate Bitcoin Configuration File with the Appropriate Permissions
cat << EOF | sudo tee /etc/bitcoin.conf
server=1
$(rpcauth satoshi $(sudo cat /root/rpcpasswd) | grep 'rpcauth')
[micro]
#### Add nodes here via ssh tunneling (e.g. addnode=localhost:19335). ####
EOF

sudo chown root:bitcoin /etc/bitcoin.conf
sudo chmod 640 /etc/bitcoin.conf

# Configure bitcoind's Log Files; Prevents them from Filling up the Partition
cat << EOF | sudo tee /etc/logrotate.d/bitcoin
/var/lib/bitcoin/micro/debug.log {
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
sudo mkdir -p /var/log/bitcoin/micro
sudo ln -s /var/lib/bitcoin/micro/debug.log /var/log/bitcoin/micro/debug.log
sudo chown root:bitcoin -R /var/log/bitcoin
sudo chmod 660 -R /var/log/bitcoin

# Install/Setup/Enable the Uncomplicated Firewall (UFW)
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh # Open Default SSH Port
sudo ufw --force enable # Enable Firewall @ Boot and Start it now!

# Install/Setup/Enable SSH(D)
sudo sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config # Disable password login
sudo sed -i 's/X11Forwarding yes/#X11Forwarding no/g' /etc/ssh/sshd_config # Disable X11Forwarding (default value)
sudo sed -i 's/#AllowTcpForwarding yes/AllowTcpForwarding Local/g' /etc/ssh/sshd_config # Only allow local port forwarding
sudo sed -i 's/#.*StrictHostKeyChecking ask/\ \ \ \ StrictHostKeyChecking yes/g' /etc/ssh/ssh_config # Enable strict host verification
echo -e "\nMatch User *,"'!'"stratum,"'!'"root,"'!'"$USER" | sudo tee -a /etc/ssh/sshd_config
echo -e "\tAllowTCPForwarding no" | sudo tee -a /etc/ssh/sshd_config
echo -e "\tPermitTTY no" | sudo tee -a /etc/ssh/sshd_config
echo -e "\tForceCommand /usr/sbin/nologin" | sudo tee -a /etc/ssh/sshd_config
echo -e "\nMatch User p2p" | sudo tee -a /etc/ssh/sshd_config
echo -e "\tPermitTTY no" | sudo tee -a /etc/ssh/sshd_config
echo -e "\tPermitOpen localhost:19333 localhost:3333" | sudo tee -a /etc/ssh/sshd_config

# Setup a "no login" user called "p2p"
sudo useradd -s /bin/false -m -d /home/p2p p2p

# Create (p2p) .ssh folder; Set ownership and permissions
sudo mkdir -p /home/p2p/.ssh
sudo touch /home/p2p/.ssh/authorized_keys
sudo chown -R p2p:p2p /home/p2p/.ssh
sudo chmod 700 /home/p2p/.ssh
sudo chmod 600 /home/p2p/.ssh/authorized_keys

# Generate public/private keys (non-encrytped)
sudo ssh-keygen -t ed25519 -f /root/.ssh/p2pkey -N "" -C ""

# Create .ssh folder; Set ownership and permissions
sudo mkdir -p ~/.ssh
sudo touch ~/.ssh/authorized_keys
sudo chown -R $USER:$USER ~/.ssh
sudo chmod 700 ~/.ssh
sudo chmod 600 ~/.ssh/authorized_keys

# Create known_hosts file
sudo touch /root/.ssh/known_hosts

# Create systemd Service File
cat << EOF | sudo tee /etc/systemd/system/p2pssh@.service
[Unit]
Description=AutoSSH %I Tunnel Service
Before=bitcoind.service
After=network-online.target

[Service]
Environment="AUTOSSH_GATETIME=0"
EnvironmentFile=/etc/default/p2pssh@%i
ExecStart=/usr/bin/autossh -M 0 -NT -o ServerAliveInterval=30 -o ExitOnForwardFailure=yes -o "ServerAliveCountMax 3" -i /root/.ssh/p2pkey -L \${LOCAL_PORT}:localhost:19333 -p \${TARGET_PORT} p2p@\${TARGET}

RestartSec=5
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Compile/Install CKProxy
git clone https://github.com/satoshiware/ckpool
cd ckpool
./autogen.sh
./configure -prefix /usr
make clean
make
sudo make install
cd ..; rm -rf ckpool

# Create a ckproxy System User
sudo useradd --system --shell=/sbin/nologin ckproxy

# Create CKProxy Log Folders
sudo mkdir -p /var/log/stratum
sudo chown root:ckproxy -R /var/log/stratum
sudo chmod 670 -R /var/log/stratum

# Create ckproxy.service (Systemd)
LOCAL_STRATUM_PORT=$(python -c 'import socket; s=socket.socket(); s.bind(("", 0)); print(s.getsockname()[1]); s.close()')
cat << EOF | sudo tee /etc/systemd/system/ckproxy.service
[Unit]
Description=Stratum Proxy Server
After=network-online.target
Wants=bitcoind.service

[Service]
ExecStart=/usr/bin/ckproxy --log-shares --killold --config /etc/ckproxy.conf

Type=simple
PIDFile=/tmp/ckproxy/main.pid
Restart=always
RestartSec=30
TimeoutStopSec=30

### Run as stratum:stratum ###
User=ckproxy
Group=ckproxy

### Hardening measures ###
ProtectSystem=full
ProtectHome=true
NoNewPrivileges=true
PrivateDevices=true

[Install]
WantedBy=multi-user.target
EOF

# Create Stratum autossh (Systemd)
# Note: Reusing the p2pssh environment file and p2pkey authentication.
cat << EOF | sudo tee /etc/systemd/system/stratssh@.service
[Unit]
Description=Stratum AutoSSH %I Tunnel Service
Before=ckproxy.service
After=network-online.target

[Service]
Environment="AUTOSSH_GATETIME=0"
EnvironmentFile=/etc/default/p2pssh@%i
ExecStart=/usr/bin/autossh -M 0 -NT -o ServerAliveInterval=30 -o ExitOnForwardFailure=yes -o "ServerAliveCountMax 3" -i /root/.ssh/p2pkey -L ${LOCAL_STRATUM_PORT}:localhost:3333 -p \${TARGET_PORT} p2p@\${TARGET}

RestartSec=5
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Generating Strong Passphrase
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

# Generate Wallets
sudo -u bitcoin /usr/bin/bitcoin-cli -micro -datadir=/var/lib/bitcoin -conf=/etc/bitcoin.conf --named createwallet wallet_name="watch" disable_private_keys=true descriptors=false load_on_startup=true
sudo -u bitcoin /usr/bin/bitcoin-cli -micro -datadir=/var/lib/bitcoin -conf=/etc/bitcoin.conf --named createwallet wallet_name="import" descriptors=false load_on_startup=true
sudo -u bitcoin /usr/bin/bitcoin-cli -micro -datadir=/var/lib/bitcoin -conf=/etc/bitcoin.conf --named createwallet wallet_name="mining" passphrase=$(sudo cat /root/passphrase) load_on_startup=true
sudo -u bitcoin /usr/bin/bitcoin-cli -micro -datadir=/var/lib/bitcoin -conf=/etc/bitcoin.conf --named createwallet wallet_name="bank" passphrase=$(sudo cat /root/passphrase) load_on_startup=true

# Create ckproxy Configuration File
MININGADDRESS=$(btc -rpcwallet=mining getnewaddress "ckproxy")
echo "Please enter your email to receive notifications from the pool"; read MININGEMAIL
cat << EOF | sudo tee /etc/ckproxy.conf
{
"btcd" : [
$(printf '\t'){
$(printf '\t')"url" : "localhost:19332",
$(printf '\t')"auth" : "satoshi",
$(printf '\t')"pass" : "$(sudo cat /root/rpcpasswd)",
$(printf '\t')"notify" : true
$(printf '\t')}
],
"proxy" : [
$(printf '\t'){
$(printf '\t')"url" : "localhost:${LOCAL_STRATUM_PORT}",
$(printf '\t')"auth" : "${MININGADDRESS}.${MININGEMAIL}",
$(printf '\t')"pass" : "x"
$(printf '\t')}
],
"btcaddress" : "",
"serverurl" : [
$(printf '\t')"0.0.0.0:3333"
],
"mindiff" : 1,
"startdiff" : 42,
"maxdiff" : 0,
"zmqblock" : "tcp://127.0.0.1:28332",
"logdir" : "/var/log/stratum"
}
Comments from here on are ignored.
EOF

sudo chown root:ckproxy /etc/ckproxy.conf
sudo chmod 440 /etc/ckproxy.conf

# Reload/Enable System Control for ckproxy
sudo systemctl daemon-reload
sudo systemctl enable ckproxy

# Create Aliases to lock and unlocks (24 Hours) wallets
echo "alias unlockwallets=\"btc -rpcwallet=mining walletpassphrase \$(sudo cat /root/passphrase) 86400; btc -rpcwallet=bank walletpassphrase \$(sudo cat /root/passphrase) 86400\"" | sudo tee -a /etc/bash.bashrc
echo "alias lockwallets=\"btc -rpcwallet=mining walletlock; btc -rpcwallet=bank walletlock\"" | sudo tee -a /etc/bash.bashrc

# Backup Wallets
sudo mkdir -p ~/backup
sudo install -C -m 400 -o $USER -g $USER /var/lib/bitcoin/micro/wallets/mining/wallet.dat ~/backup/mining.dat
sudo install -C -m 400 -o $USER -g $USER /var/lib/bitcoin/micro/wallets/bank/wallet.dat ~/backup/bank.dat

# Record (by Hand) the Passphrase
echo "The wallets are encrypted with a passphrase."
echo "Write down (by hand) to backup this passphrase: $(sudo cat /root/passphrase)"
read -p "Press any key to continue ..."

# Verify HandWritten Passphrase
clear; read -p "enter the passphrase: "
if [[ ! "$(sudo cat /root/passphrase)" == "$REPLY" ]]; then
  echo "Passphrase incorrect. Try again!"
  echo "Write down (by hand) to backup this passphrase: $(sudo cat /root/passphrase)"
  read -p "Press any key to continue ..."

  clear; read -p "enter the passphrase: "
  if [[ ! "$(sudo cat /root/passphrase)" == "$REPLY" ]]; then
    echo "Passphrase incorrect. Try again (last chance)!"
    echo "Write down (by hand) to backup this passphrase: $(sudo cat /root/passphrase)"
    read -p "Press any key to continue ..."

    clear; read -p "enter the passphrase: "
    if [[ ! "$(sudo cat /root/passphrase)" == "$REPLY" ]]; then
      echo "Error: passphrase not recorded and/or entered by the user successfully!"
      exit 1
    fi
  fi
fi

# Remind user to restart the instance
clear; echo "Don't forget to exit to PowerShell and restart this instance: \"wsl -t \$INSTANCE\""
