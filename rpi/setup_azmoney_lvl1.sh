### Login as satoshi #############################################################################################################################################################
######## who are we logged in at?? root or satoshi ###############################################################################################################################

#!/bin/bash

# Run latest updates and upgrades
sudo apt-get -y update
sudo apt-get -y upgrade

# Install Packages
sudo apt-get -y install wget ufw autossh
###psmisc (kill all)#####################################################################################################################################################################################
### does it already have curl? Can't we donwload with that??? and get rid of wget########################################################################################################################

# Download, Verify Checksum
cd ~
wget https://github.com/satoshiware/bitcoin/releases/download/v23001/bitcoin-arm-linux-gnueabihf.tar.gz
if [[ ! "$(sha256sum ~/bitcoin-arm-linux-gnueabihf.tar.gz)" == *"df74eb09096a722c42e0b84ff96bc29f01380b4460729ea30cacba96ad6af7a6"* ]]; then
        echo "Error: sha256sum for file \"bitcoin-arm-linux-gnueabihf.tar.gz\" was not what was expected!"
        exit 1
fi

# Install Binaries
tar -xzf bitcoin-arm-linux-gnueabihf.tar.gz
sudo install -m 0755 -o root -g root -t /usr/bin bitcoin-install/bin/*
rm bitcoin-arm-linux-gnueabihf.tar.gz
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

# Create a bitcoin System User
sudo useradd --system --shell=/sbin/nologin bitcoin

# Wrap the Bitcoin CLI Binary with its Runtime Configuration
alias btc="sudo -u bitcoin /usr/bin/bitcoin-cli -micro -datadir=/var/lib/bitcoin -conf=/etc/bitcoin.conf"
echo "alias btc=\"sudo -u bitcoin /usr/bin/bitcoin-cli -micro -datadir=/var/lib/bitcoin -conf=/etc/bitcoin.conf\"" | sudo tee -a /etc/bash.bashrc # Reestablish alias @ boot

# Generate Bitcoin Configuration File with the Appropriate Permissions
cat << EOF | sudo tee /etc/bitcoin.conf
#server=0 # Accept JSON-RPC commands.
#rpcauth=satoshi:e826...267$R07...070d # Username and hashed password for JSON-RPC connections
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

# Setup/Enable the Uncomplicated Firewall (UFW)
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh # Open Default SSH Port
sudo ufw --force enable # Enable Firewall @ Boot and Start it now!

# Install/Setup/Enable SSH(D)
sudo sed -i 's/#.*StrictHostKeyChecking ask/\ \ \ \ StrictHostKeyChecking yes/g' /etc/ssh/ssh_config # Enable strict host verification
sudo sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config # Disable password login
sudo sed -i 's/X11Forwarding yes/#X11Forwarding no/g' /etc/ssh/sshd_config # Disable X11Forwarding (default value)
sudo sed -i 's/#AllowTcpForwarding yes/AllowTcpForwarding Local/g' /etc/ssh/sshd_config # Only allow local port forwarding
echo -e "\nMatch User *,"'!'"stratum,"'!'"root,"'!'"satoshi" | sudo tee -a /etc/ssh/sshd_config
echo -e "\tAllowTCPForwarding no" | sudo tee -a /etc/ssh/sshd_config
echo -e "\tPermitTTY no" | sudo tee -a /etc/ssh/sshd_config
echo -e "\tForceCommand /usr/sbin/nologin" | sudo tee -a /etc/ssh/sshd_config
echo -e "\nMatch User stratum" | sudo tee -a /etc/ssh/sshd_config
echo -e "\tPermitTTY no" | sudo tee -a /etc/ssh/sshd_config
echo -e "\tPermitOpen localhost:3333" | sudo tee -a /etc/ssh/sshd_config

# Setup a "no login" user called "stratum"
sudo useradd -s /bin/false -m -d /home/stratum stratum

# Create (stratum) .ssh folder; Set ownership and permissions
sudo mkdir -p /home/stratum/.ssh
sudo touch /home/stratum/.ssh/authorized_keys
sudo chown -R stratum:stratum /home/stratum/.ssh
sudo chmod 700 /home/stratum/.ssh
sudo chmod 600 /home/stratum/.ssh/authorized_keys

# Generate public/private keys (non-encrytped)
sudo ssh-keygen -t ed25519 -f /root/.ssh/p2pkey -N "" -C ""

# Create known_hosts file
sudo touch /root/.ssh/known_hosts

# Create systemd Service File p2pssh
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

# Generating Strong Passphrase
STRONGPASSPF=$(openssl rand -base64 24)
STRONGPASSPF=${STRONGPASSPF//\//0} # Replace '/' characters with '0'
STRONGPASSPF=${STRONGPASSPF//+/1} # Replace '+' characters with '1'
STRONGPASSPF=${STRONGPASSPF//=/} # Replace '=' characters with ''
STRONGPASSPF=${STRONGPASSPF//O/0} # Replace 'O' (o) characters with '0'
STRONGPASSPF=${STRONGPASSPF//l/1} # Replace 'l' (L) characters with '1'
echo $STRONGPASSPF | sudo tee /root/passphrase
sudo chmod 400 /root/passphrase

# Create Fail Safe SSH Key Pair
ssh-keygen -t ed25519 -C "# SSH Fail Safe" -N $(sudo cat /root/passphrase) -f ~/.ssh/ssh_key_failsafe

# Authorize New Key
sed -i '/# SSH Fail Safe/d' ~/.ssh/authorized_keys # Delete preexisting "Fail Safe Key" if it exists
cat ~/.ssh/ssh_key_failsafe.pub | sudo tee -a ~/.ssh/authorized_keys # Add "Fail Safe Key" to list of authorized keys
sudo cat ~/.ssh/authorized_keys # Verify fail safe key was successfully added to authorized_keys file

# Generate Wallets
btc --named createwallet wallet_name="watch" disable_private_keys=true descriptors=false load_on_startup=true
btc --named createwallet wallet_name="import" descriptors=false load_on_startup=true
btc --named createwallet wallet_name="mining" passphrase=$(sudo cat /root/passphrase) load_on_startup=true
btc --named createwallet wallet_name="bank" passphrase=$(sudo cat /root/passphrase) load_on_startup=true

# Create Alias Unlocks wallets for 24 Hours
echo "alias unlockwallets=\"btc -rpcwallet=mining walletpassphrase \$(sudo cat /root/passphrase) 86400; btc -rpcwallet=bank walletpassphrase \$(sudo cat /root/passphrase) 86400\"" | sudo tee -a /etc/bash.bashrc # Restores alias @ boot
echo "alias lockwallets=\"btc -rpcwallet=mining walletlock; btc -rpcwallet=bank walletlock\"" | sudo tee -a /etc/bash.bashrc # Restores alias @ boot

# Backup Wallets and SSH Fail Safe Key ("watch" and "import" wallets not included)
mkdir ~/backup
sudo install -C -m 400 -o satoshi -g satoshi /var/lib/bitcoin/micro/wallets/mining/wallet.dat ~/backup/mining.dat
sudo install -C -m 400 -o satoshi -g satoshi /var/lib/bitcoin/micro/wallets/bank/wallet.dat ~/backup/bank.dat
sudo install -C -m 400 -o satoshi -g satoshi ~/.ssh/ssh_key_failsafe ~/backup

# Record (by Hand) the Passphrase
echo "The wallets and the \"ssh fail safe key\" are encrypted with a passphrase."
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

# Reload/Enable System Control for new processes, erase bash history, and restart
sudo systemctl daemon-reload
sudo systemctl enable bitcoind
sudo reboot
