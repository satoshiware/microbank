### Login as satoshi
######## who are we logged in at?? root or satoshi

sudo apt-get -y update
sudo apt-get -y upgrade

# Install Packages
sudo apt-get -y install wget psmisc ufw ssh autossh build-essential yasm autoconf automake libtool libzmq3-dev git

# Download, Verify Checksum
cd ~
wget https://github.com/satoshiware/bitcoin/releases/download/v23001/bitcoin-arm-linux-gnueabihf.tar.gz
sha256sum ~/bitcoin-arm-linux-gnueabihf.tar.gz # df74eb09096a722c42e0b84ff96bc29f01380b4460729ea30cacba96ad6af7a6   ################ Verify Checksum###############################

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
at << EOF | sudo tee /etc/bitcoin.conf
server=1 # Accept JSON-RPC commands.
#rpcauth=satoshi:e826...267$R07...070d # Username and hashed password for JSON-RPC connections
#rest=0 # Accept public REST requests.
txindex=1 # Maintain a full transaction index.
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
echo -e "\nMatch User *,"'!'"p2p,"'!'"stratum,"'!'"root,"'!'"satoshi" | sudo tee -a /etc/ssh/sshd_config
echo -e "\tAllowTCPForwarding no" | sudo tee -a /etc/ssh/sshd_config
echo -e "\tPermitTTY no" | sudo tee -a /etc/ssh/sshd_config
echo -e "\tForceCommand /usr/sbin/nologin" | sudo tee -a /etc/ssh/sshd_config
echo -e "\nMatch User p2p" | sudo tee -a /etc/ssh/sshd_config
echo -e "\tPermitTTY no" | sudo tee -a /etc/ssh/sshd_config
echo -e "\tPermitOpen localhost:19333 localhost:3333" | sudo tee -a /etc/ssh/sshd_config
echo -e "\nMatch User stratum" | sudo tee -a /etc/ssh/sshd_config
echo -e "\tPermitTTY no" | sudo tee -a /etc/ssh/sshd_config
echo -e "\tPermitOpen localhost:3333" | sudo tee -a /etc/ssh/sshd_config

# Setup a "no login" user called "p2p"
sudo useradd -s /bin/false -m -d /home/p2p p2p

#Create (p2p) .ssh folder; Set ownership and permissions
sudo mkdir -p /home/p2p/.ssh
sudo touch /home/p2p/.ssh/authorized_keys
sudo chown -R p2p:p2p /home/p2p/.ssh
sudo chmod 700 /home/p2p/.ssh
sudo chmod 600 /home/p2p/.ssh/authorized_keys

# Setup a "no login" user called "stratum"
sudo useradd -s /bin/false -m -d /home/stratum stratum

# Create (stratum) .ssh folder; Set ownership and permissions
sudo mkdir -p /home/stratum/.ssh
sudo touch /home/stratum/.ssh/authorized_keys
sudo chown -R stratum:stratum /home/stratum/.ssh
sudo chmod 700 /home/stratum/.ssh
sudo chmod 600 /home/stratum/.ssh/authorized_keys

# Generate public/private keys (non-encytped)
sudo ssh-keygen -t ed25519 -f /root/.ssh/p2pkey -N "" -C ""

# Create (satoshi) .ssh folder; Set ownership and permissions
sudo mkdir -p /home/satoshi/.ssh
sudo touch /home/satoshi/.ssh/authorized_keys
sudo chown -R satoshi:satoshi /home/satoshi/.ssh
sudo chmod 700 /home/satoshi/.ssh
sudo chmod 600 /home/satoshi/.ssh/authorized_keys

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
STRONGPASSPF="" # Erase from memory
sudo chmod 400 /root/passphrase

# Record (by Hand) the Passphrase ###########################################################################
sudo cat /root/passphrase

# Verify Hand Written Passphrase ###########################################################################
echo # Type in the passphrase in substitution of $TYPED_HANDWRITTENPASSPHRASE (keep the quotes) #########################################################
sudo cat /root/passphrase | grep "$(readline)" | wc -l  # 0 indicates it was not recorded/entered correctly    # 1 indicates that it was recorded/entered correctly ################
history -c # Clear the password from bash's history


# Create Fail Safe SSH Key Pair
sudo su satoshi # Let's use satoshi's account
sudo rm ~/.ssh/ssh_key_failsafe*
ssh-keygen -t ed25519 -C "# SSH Fail Safe" -N $(sudo cat /root/passphrase) -f ~/.ssh/ssh_key_failsafe

# Authorize New Key
sed -i '/# SSH Fail Safe/d' ~/.ssh/authorized_keys # Delete preexisting "Fail Safe Key" if it exists
cat ~/.ssh/ssh_key_failsafe.pub | sudo tee -a ~/.ssh/authorized_keys # Add "Fail Safe Key" to list of authorized keys
sudo cat ~/.ssh/authorized_keys # Verify fail safe key was successfully added to authorized_keys file

# Verify Passphrase is Enforced ############################################################################################################# need to automate this #####################
echo "passphrase:" $(sudo cat /root/passphrase) # Verify a strong passphrase is being referenced
ssh-keygen -y -P $(sudo cat /root/passphrase) -f ~/.ssh/ssh_key_failsafe # If output matches pub key, referenced passphrase is in use!




# Generate Wallets
btc --named createwallet wallet_name="watch" disable_private_keys=true descriptors=false load_on_startup=true
btc --named createwallet wallet_name="import" descriptors=false load_on_startup=true
btc --named createwallet wallet_name="mining" passphrase=$(sudo cat /root/passphrase) load_on_startup=true
btc --named createwallet wallet_name="bank" passphrase=$(sudo cat /root/passphrase) load_on_startup=true

# Create Alias Unlocks wallets for 24 Hours
alias unlockwallets="btc -rpcwallet=mining walletpassphrase \$(sudo cat /root/passphrase) 86400; btc -rpcwallet=bank walletpassphrase \$(sudo cat /root/passphrase) 86400"
echo "alias unlockwallets=\"btc -rpcwallet=mining walletpassphrase \$(sudo cat /root/passphrase) 86400; btc -rpcwallet=bank walletpassphrase \$(sudo cat /root/passphrase) 86400\"" | sudo tee -a /etc/bash.bashrc # Restores alias @ boot
alias lockwallets="btc -rpcwallet=mining walletlock; btc -rpcwallet=bank walletlock"
echo "alias lockwallets=\"btc -rpcwallet=mining walletlock; btc -rpcwallet=bank walletlock\"" | sudo tee -a /etc/bash.bashrc # Restores alias @ boot

# Verification ################################################
btc listwalletdir # Show wallets in wallets directory
btc listwallets # Show wallets that are loaded
echo "passphrase:" $(sudo cat /root/passphrase) # Verify a strong passphrase is being referenced
lockwallets # Lock wallets
btc -rpcwallet=mining walletpassphrase $(sudo cat /root/passphrase) 1 # No messages indicates passphrase is working
btc -rpcwallet=bank walletpassphrase $(sudo cat /root/passphrase) 1 # No messages indicates passphrase is working

# Backup Wallets and SSH Fail Safe Key ("watch" and "import" wallets not included)
sudo su satoshi # Let's use satoshi's account
mkdir ~/backup
sudo install -C -m 400 -o satoshi -g satoshi /var/lib/bitcoin/micro/wallets/mining/wallet.dat ~/backup/mining.dat
sudo install -C -m 400 -o satoshi -g satoshi /var/lib/bitcoin/micro/wallets/bank/wallet.dat ~/backup/bank.dat
sudo install -C -m 400 -o satoshi -g satoshi ~/.ssh/ssh_key_failsafe ~/backup











# Compile/Install CKPool/CKProxy
cd ~
git clone https://github.com/satoshiware/ckpool
cd ckpool
./autogen.sh
./configure -prefix /usr
make clean
make
sudo make install

# Create a ckpool System User
sudo useradd --system --shell=/sbin/nologin ckpool

# Create Log Folders
sudo mkdir -p /var/log/stratum
sudo chown root:ckpool -R /var/log/stratum
sudo chmod 670 -R /var/log/stratum

# Install rpcauth Utility
sudo apt-get -y install python
sudo wget https://github.com/satoshiware/bitcoin/releases/download/v23001/rpcauth.py -P /usr/share/python
sha256sum /usr/share/python/rpcauth.py # Verify Checksum b0920f6d96f8c72cee49df90ee4d0bf826bbe845596ecc056c6bc0873c146d1f #################################### Verify Checksum ############################
sudo chmod +x /usr/share/python/rpcauth.py
echo "#"\!"/bin/sh" | sudo tee /usr/share/python/rpcauth.sh
echo "python3 /usr/share/python/rpcauth.py \$1 \$2" | sudo tee -a /usr/share/python/rpcauth.sh
sudo ln -s /usr/share/python/rpcauth.sh /usr/bin/rpcauth
sudo chmod 755 /usr/bin/rpcauth

# Generate Strong Bitcoin RPC Password
BTCRPCPASSWD=$(openssl rand -base64 16)
BTCRPCPASSWD=${BTCRPCPASSWD//\//0} # Replace '/' characters with '0'
BTCRPCPASSWD=${BTCRPCPASSWD//+/1} # Replace '+' characters with '1'
BTCRPCPASSWD=${BTCRPCPASSWD//=/} # Replace '=' characters with ''
echo $BTCRPCPASSWD | sudo tee /root/rpcpasswd
BTCRPCPASSWD="" # Erase from memory
sudo chmod 400 /root/rpcpasswd

# Update Bitcoin Configuration
sudo sed -i "s/.*rpcauth.*/$(rpcauth satoshi $(sudo cat /root/rpcpasswd) | grep 'rpcauth')/g" /etc/bitcoin.conf

Create ckpool.service (Systemd)
cat << EOF | sudo tee /etc/systemd/system/ckpool.service
[Unit]
Description=Stratum Pool Server
After=network-online.target
Wants=bitcoind.service

[Service]
ExecStart=/usr/bin/ckpool --log-shares --killold --config /etc/ckpool.conf

Type=simple
PIDFile=/tmp/ckpool/main.pid
Restart=always
RestartSec=30
TimeoutStopSec=30

### Run as ckpool:ckpool ###
User=ckpool
Group=ckpool

### Hardening measures ###
ProtectSystem=full
ProtectHome=true
NoNewPrivileges=true
PrivateDevices=true

[Install]
WantedBy=multi-user.target
EOF

# Create ckproxy.service (Systemd)
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
User=ckpool
Group=ckpool

### Hardening measures ###
ProtectSystem=full
ProtectHome=true
NoNewPrivileges=true
PrivateDevices=true

[Install]
WantedBy=multi-user.target
EOF

# Create Stratum autossh (Systemd) - Note: Reusing the p2pssh environment file and p2pkey authentication.
cat << EOF | sudo tee /etc/systemd/system/stratssh@.service
[Unit]
Description=Stratum AutoSSH %I Tunnel Service
Before=ckproxy.service
After=network-online.target

[Service]
Environment="AUTOSSH_GATETIME=0"
EnvironmentFile=/etc/default/p2pssh@%i
ExecStart=/usr/bin/autossh -M 0 -NT -o ServerAliveInterval=30 -o ExitOnForwardFailure=yes -o "ServerAliveCountMax 3" -i /root/.ssh/p2pkey -L 3334:localhost:3333 -p \${TARGET_PORT} p2p@\${TARGET}

RestartSec=5
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Create ckpool Configuration File
MININGADDRESS=$(btc -rpcwallet=mining getnewaddress "ckpool")

cat << EOF | sudo tee /etc/ckpool.conf
{
"btcd" : [
$(printf '\t'){
$(printf '\t')"url" : "localhost:19332",
$(printf '\t')"auth" : "satoshi",
$(printf '\t')"pass" : "$(sudo cat /root/rpcpasswd)",
$(printf '\t')"notify" : true
$(printf '\t')}
],
"btcaddress" : "$MININGADDRESS",
"btcsig" : "",
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

sudo chown root:ckpool /etc/ckpool.conf
sudo chmod 440 /etc/ckpool.conf

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
$(printf '\t')"url" : "localhost:3334",
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

sudo chown root:ckpool /etc/ckproxy.conf
sudo chmod 440 /etc/ckproxy.conf














# Enable System Control for new Processes and Restart
sudo systemctl enable bitcoind
sudo systemctl enable ssh

########### are we minning? pool or proxy? using any big equipment???????????????????????????????????????????????????

sudo systemctl daemon-reload

###reboot now
