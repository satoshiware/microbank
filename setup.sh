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

# Select the system configuration for the remaining script to run the proper setup/installtion.
echo ""
PS3='What system configuration are we using? '
options=("WSL (Debian, x86_64)" "Debian (x86_64)" "Raspbian (ARM_32)")
select opt in "${options[@]}"
do
    case $opt in
        "WSL (Debian, x86_64)") MN_SYS_CONFIG="WSL"; break;;
        "Debian (x86_64)") MN_SYS_CONFIG="DEBIAN"; break;;
        "Raspbian (ARM_32)") MN_SYS_CONFIG="RASPBIAN"; break;;
        *) echo "Invalid option! Your input was \"$REPLY\""; break;;
    esac
done

# WSL Reminder: multiple (micro) bitcoin core instances running on the same windows machine could have port collision.
if [[ ${MN_SYS_CONFIG} = "WSL" ]]; then
    echo ""; echo "Make sure to shutdown all other Bitcoin Core (micro) instances on this Windows machine."
    echo "Port collisions will interrupt this script."; read -p "Press enter to continue ..."; echo ""
fi

# Select the node level
read -p "What node level would you like installed? (1, 2, or 3): " NDLVL
echo ${NDLVL} | sudo tee /etc/nodelevel

# Run latest updates and upgrades
sudo apt-get -y update
sudo apt-get -y upgrade

# Install Packages
sudo apt-get -y install wget psmisc autossh ssh ufw python jq
if [[ ${NDLVL} = "2" || ${NDLVL} = "3" ]]; then
    sudo apt-get -y install build-essential yasm autoconf automake libtool libzmq3-dev git

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
fi

# Download Bitcoin Core (micro), Verify Checksum
if [[ ${MN_SYS_CONFIG} = "RASPBIAN" ]]; then
    wget https://github.com/satoshiware/bitcoin/releases/download/v23001/bitcoin-arm-linux-gnueabihf.tar.gz
    if [[ ! "$(sha256sum ~/bitcoin-arm-linux-gnueabihf.tar.gz)" == *"df74eb09096a722c42e0b84ff96bc29f01380b4460729ea30cacba96ad6af7a6"* ]]; then
        echo "Error: sha256sum for file \"bitcoin-arm-linux-gnueabihf.tar.gz\" was not what was expected!"
        exit 1
    fi

    tar -xzf bitcoin-arm-linux-gnueabihf.tar.gz
    rm bitcoin-arm-linux-gnueabihf.tar.gz

else
    wget https://github.com/satoshiware/bitcoin/releases/download/v23001/bitcoin-x86_64-linux-gnu.tar.gz
    if [[ ! "$(sha256sum ~/bitcoin-x86_64-linux-gnu.tar.gz)" == *"d868e59d59e338d5dedd25e9093c9812a764b6c6dc438871caacf8e692a9e04d"* ]]; then
        echo "Error: sha256sum for file \"bitcoin-x86_64-linux-gnu.tar.gz\" was not what was expected!"
        exit 1
    fi

    tar -xzf bitcoin-x86_64-linux-gnu.tar.gz
    rm bitcoin-x86_64-linux-gnu.tar.gz
fi

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

if [[ ${NDLVL} = "2" || ${NDLVL} = "3" ]]; then
    # Generate Strong Bitcoin RPC Password
    BTCRPCPASSWD=$(openssl rand -base64 16)
    BTCRPCPASSWD=${BTCRPCPASSWD//\//0} # Replace '/' characters with '0'
    BTCRPCPASSWD=${BTCRPCPASSWD//+/1} # Replace '+' characters with '1'
    BTCRPCPASSWD=${BTCRPCPASSWD//=/} # Replace '=' characters with ''
    echo $BTCRPCPASSWD | sudo tee /root/rpcpasswd
    BTCRPCPASSWD="" # Erase from memory
    sudo chmod 400 /root/rpcpasswd
fi

# Generate Bitcoin Configuration File with the Appropriate Permissions
if [[ ${NDLVL} = "2" || ${NDLVL} = "3" ]]; then
    cat << EOF | sudo tee /etc/bitcoin.conf
server=1
$(rpcauth satoshi $(sudo cat /root/rpcpasswd) | grep 'rpcauth')
[micro]
EOF
else
    cat << EOF | sudo tee /etc/bitcoin.conf
[micro]
EOF
fi
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
if [ ${NDLVL} = "1" ]; then
    echo -e "\nMatch User *,"'!'"stratum,"'!'"root,"'!'"$USER" | sudo tee -a /etc/ssh/sshd_config;
fi
if [[ ${NDLVL} = "2" || ${NDLVL} = "3" ]]; then
    echo -e "\nMatch User *,"'!'"p2p,"'!'"root,"'!'"$USER" | sudo tee -a /etc/ssh/sshd_config
fi
echo -e "\tAllowTCPForwarding no" | sudo tee -a /etc/ssh/sshd_config
echo -e "\tPermitTTY no" | sudo tee -a /etc/ssh/sshd_config
echo -e "\tForceCommand /usr/sbin/nologin" | sudo tee -a /etc/ssh/sshd_config
if [ ${NDLVL} = "1" ]; then
    echo -e "\nMatch User stratum" | sudo tee -a /etc/ssh/sshd_config
    echo -e "\tPermitTTY no" | sudo tee -a /etc/ssh/sshd_config
    echo -e "\tPermitOpen localhost:3333" | sudo tee -a /etc/ssh/sshd_config
fi
if [[ ${NDLVL} = "2" || ${NDLVL} = "3" ]]; then
    echo -e "\nMatch User p2p" | sudo tee -a /etc/ssh/sshd_config
    echo -e "\tPermitTTY no" | sudo tee -a /etc/ssh/sshd_config
    echo -e "\tPermitOpen localhost:19333 localhost:3333" | sudo tee -a /etc/ssh/sshd_config
fi

if [ ${NDLVL} = "1" ]; then
    # Setup a "no login" user called "stratum"
    sudo useradd -s /bin/false -m -d /home/stratum stratum

    # Create (stratum) .ssh folder; Set ownership and permissions
    sudo mkdir -p /home/stratum/.ssh
    sudo touch /home/stratum/.ssh/authorized_keys
    sudo chown -R stratum:stratum /home/stratum/.ssh
    sudo chmod 700 /home/stratum/.ssh
    sudo chmod 600 /home/stratum/.ssh/authorized_keys
fi

if [[ ${NDLVL} = "2" || ${NDLVL} = "3" ]]; then
    # Setup a "no login" user called "p2p"
    sudo useradd -s /bin/false -m -d /home/p2p p2p

    # Create (p2p) .ssh folder; Set ownership and permissions
    sudo mkdir -p /home/p2p/.ssh
    sudo touch /home/p2p/.ssh/authorized_keys
    sudo chown -R p2p:p2p /home/p2p/.ssh
    sudo chmod 700 /home/p2p/.ssh
    sudo chmod 600 /home/p2p/.ssh/authorized_keys
fi

# Generate public/private keys (non-encrytped)
sudo ssh-keygen -t ed25519 -f /root/.ssh/p2pkey -N "" -C ""

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
ExecStart=/usr/bin/autossh -M 0 -NT -o ServerAliveInterval=30 -o ExitOnForwardFailure=yes -o "ServerAliveCountMax 3" -i /root/.ssh/p2pkey -L \${LOCAL_PORT}:localhost:\${FORWARD_PORT} -p \${TARGET_PORT} p2p@\${TARGET}

RestartSec=5
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Set stratum port configuration
if [ ${NDLVL} = "1" ]; then echo "3333" | sudo tee /etc/stratumport; fi
if [ ${NDLVL} = "2" ]; then
    echo $(python -c 'import socket; s=socket.socket(); s.bind(("", 0)); print(s.getsockname()[1]); s.close()') | sudo tee /etc/stratum1port
    echo $(python -c 'import socket; s=socket.socket(); s.bind(("", 0)); print(s.getsockname()[1]); s.close()') | sudo tee /etc/stratum2port
    echo $(python -c 'import socket; s=socket.socket(); s.bind(("", 0)); print(s.getsockname()[1]); s.close()') | sudo tee /etc/stratum3port
fi

if [[ ${NDLVL} = "2" || ${NDLVL} = "3" ]]; then
    if [ ${NDLVL} = "2" ]; then
        STRATUMUSER=ckproxy
    else
        STRATUMUSER=ckpool
    fi

    # Compile/Install CKPool/CKProxy
    git clone https://github.com/satoshiware/ckpool
    cd ckpool
    ./autogen.sh
    ./configure -prefix /usr
    make clean
    make
    sudo make install
    cd ..; rm -rf ckpool

    # Create a ${STRATUMUSER} System User
    sudo useradd --system --shell=/sbin/nologin ${STRATUMUSER}

    # Create ${STRATUMUSER} Log Folders
    sudo mkdir -p /var/log/stratum
    sudo chown root:${STRATUMUSER} -R /var/log/stratum
    sudo chmod 670 -R /var/log/stratum

    # Create ${STRATUMUSER}.service (Systemd)
    cat << EOF | sudo tee /etc/systemd/system/${STRATUMUSER}.service
[Unit]
Description=Stratum ${STRATUMUSER} Server
After=network-online.target
Wants=bitcoind.service

[Service]
ExecStart=/usr/bin/${STRATUMUSER} --log-shares --killold --config /etc/${STRATUMUSER}.conf

Type=simple
PIDFile=/tmp/${STRATUMUSER}/main.pid
Restart=always
RestartSec=30
TimeoutStopSec=30

### Run as ${STRATUMUSER}:${STRATUMUSER} ###
User=${STRATUMUSER}
Group=${STRATUMUSER}

### Hardening measures ###
ProtectSystem=full
ProtectHome=true
NoNewPrivileges=true
PrivateDevices=true

[Install]
WantedBy=multi-user.target
EOF
fi

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

if [[ ${NDLVL} = "2" || ${NDLVL} = "3" ]]; then
    # Create ${STRATUMUSER} Configuration File
    MININGADDRESS=$(sudo -u bitcoin /usr/bin/bitcoin-cli -micro -datadir=/var/lib/bitcoin -conf=/etc/bitcoin.conf -rpcwallet=mining getnewaddress "${STRATUMUSER}")
    echo "Please enter your email to receive notifications from the ${STRATUMUSER}"; read MININGEMAIL
    cat << EOF | sudo tee /etc/${STRATUMUSER}.conf
{
"btcd" : [
$(printf '\t'){
$(printf '\t')"url" : "localhost:19332",
$(printf '\t')"auth" : "satoshi",
$(printf '\t')"pass" : "$(sudo cat /root/rpcpasswd)",
$(printf '\t')"notify" : true
$(printf '\t')}
],
EOF
    if [ ${NDLVL} = "2" ]; then
    cat << EOF | sudo tee -a /etc/${STRATUMUSER}.conf
"proxy" : [
$(printf '\t'){
$(printf '\t')"url" : "localhost:$(sudo cat /etc/stratum1port)",
$(printf '\t')"auth" : "${MININGADDRESS}.${MININGEMAIL}",
$(printf '\t')"pass" : "x"
$(printf '\t')},
$(printf '\t'){
$(printf '\t')"url" : "localhost:$(sudo cat /etc/stratum2port)",
$(printf '\t')"auth" : "${MININGADDRESS}.${MININGEMAIL}",
$(printf '\t')"pass" : "x"
$(printf '\t')},
$(printf '\t'){
$(printf '\t')"url" : "localhost:$(sudo cat /etc/stratum3port)",
$(printf '\t')"auth" : "${MININGADDRESS}.${MININGEMAIL}",
$(printf '\t')"pass" : "x"
$(printf '\t')}
],
"btcaddress" : "",
EOF
    else # NDLVL = 3
    cat << EOF | sudo tee -a /etc/${STRATUMUSER}.conf
"btcaddress" : "${MININGADDRESS}",
"btcsig" : "",
EOF
    fi
    cat << EOF | sudo tee -a /etc/${STRATUMUSER}.conf
"serverurl" : [
$(printf '\t')"0.0.0.0:3333"
],
"mindiff" : 1,
"startdiff" : 42,
"maxdiff" : 0,
"zmqblock" : "tcp://127.0.0.1:28332",
"logdir" : "/var/log/stratum"
}
EOF

    sudo chown root:${STRATUMUSER} /etc/${STRATUMUSER}.conf
    sudo chmod 440 /etc/${STRATUMUSER}.conf

    # Reload/Enable System Control for ${STRATUMUSER}
    sudo systemctl daemon-reload
    sudo systemctl enable ${STRATUMUSER}
fi

# Create Aliases to lock and unlocks (24 Hours) wallets
echo "alias unlockwallets=\"btc -rpcwallet=mining walletpassphrase \$(sudo cat /root/passphrase) 86400; btc -rpcwallet=bank walletpassphrase \$(sudo cat /root/passphrase) 86400\"" | sudo tee -a /etc/bash.bashrc
echo "alias lockwallets=\"btc -rpcwallet=mining walletlock; btc -rpcwallet=bank walletlock\"" | sudo tee -a /etc/bash.bashrc

# Backup Wallets
sudo mkdir -p ~/backup
sudo chown -R $USER:$USER ~/backup
sudo install -C -m 400 -o $USER -g $USER /var/lib/bitcoin/micro/wallets/mining/wallet.dat ~/backup/mining.dat
sudo install -C -m 400 -o $USER -g $USER /var/lib/bitcoin/micro/wallets/bank/wallet.dat ~/backup/bank.dat

# Record (by Hand) the Passphrase
echo "The wallets are encrypted with a passphrase."
echo "Write down (by hand) to backup this passphrase: $(sudo cat /root/passphrase)"
read -p "Press any enter to continue ..."

# Verify HandWritten Passphrase
clear; read -p "enter the passphrase: "
if [[ ! "$(sudo cat /root/passphrase)" == "$REPLY" ]]; then
  echo "Passphrase incorrect. Try again!"
  echo "Write down (by hand) to backup this passphrase: $(sudo cat /root/passphrase)"
  read -p "Press any enter to continue ..."

  clear; read -p "enter the passphrase: "
  if [[ ! "$(sudo cat /root/passphrase)" == "$REPLY" ]]; then
    echo "Passphrase incorrect. Try again (last chance)!"
    echo "Write down (by hand) to backup this passphrase: $(sudo cat /root/passphrase)"
    read -p "Press any enter to continue ..."

    clear; read -p "enter the passphrase: "
    if [[ ! "$(sudo cat /root/passphrase)" == "$REPLY" ]]; then
      echo "Error: passphrase not recorded and/or entered by the user successfully!"
      exit 1
    fi
  fi
fi

# Change Default Ports (WSL only)
if [[ ${MN_SYS_CONFIG} = "WSL" ]]; then
    read -p "Would you like to change the default ports? (y|n): "
    if [[ ${REPLY} = "y" || ${REPLY} = "Y" ]]; then
        echo "This script only works once on a fresh install and cannot be undone automatically!"
        echo "If port changes have already been changed, new changes will need to be done manually."
        read -p "Enter new Bitcoin Core (micro) port (default = 19333): "; MICROPORT="$REPLY"
        read -p "Enter new RPC (micro) port (default = 19332): "; RPCPORT="$REPLY"
        read -p "Enter new Stratum port (default = 3333): "; STRATPORT="$REPLY"
        read -p "Enter new SSH port (default = 22): "; SSHPORT="$REPLY"

        # Change SSH port in sshd config
        sudo sed -i "s/#Port 22/Port ${SSHPORT}/g" /etc/ssh/sshd_config

        # Update firewall
        sudo ufw delete allow 22/tcp
        sudo ufw allow ${SSHPORT}/tcp

        # Change Bitcoin Core (micro) port in sshd_config
        sudo sed -i "s/19333/${MICROPORT}/g" /etc/ssh/sshd_config

        # Change RPC Bitcoin Core (micro) port in and ckproxy.conf
        sudo sed -i "s/19332/${RPCPORT}/g" /etc/ckproxy.conf
        sudo sed -i "s/19332/${RPCPORT}/g" /etc/ckpool.conf

        # Add new ports to the Bitcoin (micro) configuration file
        echo "port=${MICROPORT}" | sudo tee -a /etc/bitcoin.conf
        echo "rpcport=${RPCPORT}" | sudo tee -a /etc/bitcoin.conf

        # Change Stratum port in and ckproxy/ckpool.conf, sshd_config, and p2pssh@stratum environment file
        sudo sed -i "s/3333/${STRATPORT}/g" /etc/ckproxy.conf
        sudo sed -i "s/3333/${STRATPORT}/g" /etc/ckpool.conf
        sudo sed -i "s/3333/${STRATPORT}/g" /etc/ssh/sshd_config
        echo "${STRATPORT}" | sudo tee /etc/stratumport;
    fi
fi

# Generate Micronode Information
echo "This file contains important information on your \"$(hostname)\" micronode." | tee /etc/micronode.info > /dev/null
echo "It can be used to establish p2p and stratum connections over ssh." | tee -a /etc/micronode.info > /dev/null
echo "" | tee -a /etc/micronode.info > /dev/null

read -p "What is your (hub) name? "; echo "Name: $REPLY" | tee -a /etc/micronode.info > /dev/null
echo "Level: ${NDLVL}" | tee -a /etc/micronode.info > /dev/null
echo "Time Stamp: $(date +%s)" | tee -a /etc/micronode.info > /dev/null
echo "" | tee -a /etc/micronode.info > /dev/null

read -p "What is the address to this micronode? "; echo "Address: $REPLY" | tee -a /etc/micronode.info > /dev/null
echo "" | tee -a /etc/micronode.info > /dev/null

if [ -z ${SSHPORT+x} ]; then SSHPORT="22"; fi
echo "SSH Port: ${SSHPORT}" | tee -a /etc/micronode.info > /dev/null
if [ -z ${MICROPORT+x} ]; then MICROPORT="19333"; fi
echo "Micro Port: ${MICROPORT}" | tee -a /etc/micronode.info > /dev/null
if [ -z ${STRATPORT+x} ]; then STRATPORT="3333"; fi
echo "Stratum Port: ${STRATPORT}" | tee -a /etc/micronode.info > /dev/null
echo "" | tee -a /etc/micronode.info > /dev/null

echo "Host Key (Public): $(sudo cat /etc/ssh/ssh_host_ed25519_key.pub | sed 's/ root@.*//')" | tee -a /etc/micronode.info > /dev/null
echo "P2P Key (Public): $(sudo cat /root/.ssh/p2pkey.pub)" | tee -a /etc/micronode.info > /dev/null

sudo chmod 400 /etc/micronode.info

# Install the micronode connect utility (mnconnect.sh)
bash ~/micronode/mnconnect.sh -i

# Remind user to restart
if [[ ${MN_SYS_CONFIG} = "WSL" ]]; then
    clear; echo "Don't forget to exit to PowerShell and restart this instance: \"wsl -t \$INSTANCE\""
else
    clear; echo "Now, just restart the machine and it's ready to go."
fi
