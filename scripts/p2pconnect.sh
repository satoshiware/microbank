#!/bin/bash

###todo:
      # finish "--view"

# Make sure we are not running as root, but that we have sudo privileges.
if [ "$(id -u)" = "0" ]; then
   echo "This script must NOT be run as root (or with sudo)!"
   exit 1
elif [ "$(sudo -l | grep '(ALL : ALL) ALL' | wc -l)" = 0 ]; then
   echo "You do not have enough sudo privileges!"
   exit 1
fi

# Install this script (p2pconnect) in /usr/local/sbin
if [[ $1 = "-i" || $1 = "--install" ]]; then
    echo "Installing this script (p2pconnect) in /usr/local/sbin/"
    if [ ! -f /usr/local/sbin/p2pconnect ]; then
        sudo cat $0 | sed '/Install this script/d' | sudo tee /usr/local/sbin/p2pconnect > /dev/null
        sudo sed -i 's/$1 = "-i" || $1 = "--install"/"a" = "b"/' /usr/local/sbin/p2pconnect # Make it so this code won't run again in the newly installed script.
        sudo chmod +x /usr/local/sbin/p2pconnect
    else
        echo "\"p2pconnect\" already exists in /usr/local/sbin!"
        read -p "Would you like to uninstall it? (y|n): "
        if [[ "${REPLY}" = "y" || "${REPLY}" = "Y" ]]; then
            sudo rm /usr/local/sbin/p2pconnect
        fi
    fi
    exit 0
fi

# Make sure this script is installed
if [ ! -f /usr/local/sbin/p2pconnect ]; then
    echo "Error: this script is not yet installed to \"/usr/local/sbin/p2pconnect\"!"
    echo "Rerun this script with the \"-i\" or \"--install\" parameter!"
    exit 1
fi

# See which p2pconnect parameter was passed and execute accordingly
if [[ $1 = "-h" || $1 = "--help" ]]; then # Show all possible paramters
    cat << EOF
    Options:
      -i, --install     Install this script (p2pconnect) in /usr/local/sbin/
      -h, --help        Display this help message and exit
      -n, --in          Configure inbound cluster connection (p2p <-- wallet, p2p <-- stratum, or p2p <-- electrum)
      -p, --p2p         Make p2p inbound/outbound connections (p2p <--> p2p)
      -v, --view        See all configured connections and view status
      -d, --delete      Delete a connection
      -f, --info        Get the connection parameters for this node
      -g, --generate    Generate micronode information file (/etc/micronode.info) with connection parameters for this node
EOF

elif [[ $1 = "-n" || $1 = "--in" ]]; then # Configure inbound cluster connection (p2p <-- wallet, p2p <-- stratum, or p2p <-- electrum)
    echo "Let's configure an inbound connection from a wallet, stratum, or electrum node!"
    read -p "What would you like to call this connection? (e.g. \"wallet\", \"stratum\", or \"electrum\"): " CONNNAME
    read -p "What is the node's public key: " PUBLICKEY
    read -p "What's the nodes UID? (Unique ID): " TMSTAMP # Node UIDs are based on unix time stamps

    if ! [[ ${TMSTAMP} -gt 1690000000 ]]; then
        echo "Error! Not a valid time stamp!"
        exit 1
    fi

    echo "${PUBLICKEY} # ${CONNNAME}, ${TMSTAMP}, Cluster Connection" | sudo tee -a /home/p2p/.ssh/authorized_keys

elif [[ $1 = "-p" || $1 = "--p2p" ]]; then # Make p2p inbound/outbound connections (p2p <--> p2p)
    if [[ $(ls /etc/default/p2pssh*  2> /dev/null | wc -l) -ge "8" ]]; then
        echo "Number of outbound connections is maxed out!"
        echo "Bitcoin Core only supports 8 outbound connections!"
        exit 1
    fi

    echo "Let's configure a (two-way) connection with another bank!"
    read -p "What would you like to call this connection: " CONNNAME
    read -p "What is the banks's p2p public key: " P2PKEY
    read -p "What's the bank's p2p UID? (Unique ID): " TMSTAMP # Node UIDs are based on unix time stamps

    if ! [[ ${TMSTAMP} -gt 1690000000 ]]; then
        echo "Error! Not a valid time stamp!"
        exit 1
    fi

    # With the parameters collected, set the inboud configuration
    echo "${P2PKEY} # ${CONNNAME}, ${TMSTAMP}, P2P" | sudo tee -a /home/p2p/.ssh/authorized_keys

    echo "Now, let's configure the outbound parameters!"
    read -p "What's the bank's host public key: " HOSTKEY
    read -p "What's the bank's address: " TARGETADDRESS
    read -p "What's the bank's SSH port? (default = 22): " SSHPORT; if [ -z $SSHPORT ]; then SSHPORT="22"; fi
    read -p "What's the bank's port for the (microcurrency) Bitcoin Core? (default = 19333): " MICROPORT; if [ -z $MICROPORT ]; then MICROPORT="19333"; fi

    # Update known_hosts
    HOSTSIG=$(ssh-keyscan -p ${SSHPORT} -H ${TARGETADDRESS})
    if [[ "${HOSTSIG}" == *"${HOSTKEY}"* ]]; then
        echo "${HOSTSIG} # ${CONNNAME}, ${TMSTAMP}, ${TARGETADDRESS}:${SSHPORT}, P2P" | sudo tee -a /root/.ssh/known_hosts
    else
        echo "CRITICAL ERROR: REMOTE HOST IDENTIFICATION DOES NOT MATCH GIVEN HOST KEY!!"
        exit 1
    fi

    # Create p2pssh@ environment file and start its corresponding systemd service
    LOCALMICROPORT=$(python3 -c 'import socket; s=socket.socket(); s.bind(("", 0)); print(s.getsockname()[1]); s.close()')
    cat << EOF | sudo tee /etc/default/p2pssh@${TMSTAMP}
# ${CONNNAME}
LOCAL_PORT=${LOCALMICROPORT}
FORWARD_PORT=${MICROPORT}
TARGET=${TARGETADDRESS}
TARGET_PORT=${SSHPORT}
EOF
    sudo systemctl enable p2pssh@${TMSTAMP} --now

    # Add the outbound connection to Bitcoin Core (micro) and update bitcoin.conf to be reestablish automatically upon restart or boot up
    sudo -u bitcoin /usr/bin/bitcoin-cli -micro -datadir=/var/lib/bitcoin -conf=/etc/bitcoin.conf addnode localhost:${LOCALMICROPORT} "add"
    echo "# ${CONNNAME}, ${TMSTAMP}, ${TARGETADDRESS}:${SSHPORT}" | sudo tee -a /etc/bitcoin.conf # Add comment to the bitcoin.conf file
    echo "addnode=localhost:${LOCALMICROPORT}" | sudo tee -a /etc/bitcoin.conf # Add connection

elif [[ $1 = "-v" || $1 = "--view" ]]; then # See all configured connections and view status
    echo "you made it buddy to --view"
        # Inbound
                # Level 1 Mining
    #                       sudo cat /home/stratum/.ssh/authorized_keys # Show all
                # level 2/3 P2P & Stratum
    #                       sudo cat /home/p2p/.ssh/authorized_keys # Only show STRATUM // no need to filter on level 2
                # Level 3 Remote Mining
    #                       sudo cat /home/p2p/.ssh/authorized_keys # Only show REMOTE

        # Outbound
                # level 1/2 P2P & Stratum
    #                       sudo cat /root/.ssh/known_hosts
    #                       cat /etc/bitcoin.conf
                # level 1/2 P2P
    #                       ls -all /etc/default/p2pssh*p2p
                # level 1/2 STRATUM
    #                       ls -all /etc/default/p2pssh*stratum

        # P2P (Level 3 Only)
                # Inbound
    #                       sudo cat /home/p2p/.ssh/authorized_keys # Only show P2P
                # Outbound
    #                       sudo cat /root/.ssh/known_hosts
    #                       ls -all /etc/default/p2pssh*lvl3
    #                       cat /etc/bitcoin.conf

         ########## level 1 only

    # Level 1 -

        # if we assume it is all ok, what do we hope to see with the connections?
                # the details of the connections: name, time, address, outbound, inbound, mining, IP?
                # does the node show a connection
        # outbound

        #       {CONNNAME}, ${TMSTAMP}, ${TARGETADDRESS}:${SSHPORT}     # a

        #       1 p2p outbound - 1 service file and 1 environment file
        #       1 stratum outbound - 1 service file and 1 environment file


        # Level 1 has 1 outbound connection and multiple



#!!!!!!!update forum or wsl/readme.md!!# With WSL, the host drive is already mounted. It can just be copied with cp (e.g. "cp -rf ~/backup /mnt/c/Users/$USERNAME/Desktop")

#update p2pconnect to open/close port for local miner.
    #   sudo ufw allow from 192.168.1.243 to any port 3333 # (whatever is the port)





    # Search in stratum|p2p authorized_keys to match the timestamp with the . You know, we could just disconnect everyone!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

#   ss -t -a | grep ssh
#   ipaddr="192.168.1.240"
#   ddport="42682"
#   sdport="42676"

#   cat /var/log/auth.log | grep "Accepted publickey for.*${ipaddr}.*${ddport}" # what about the stratum user instead of p2p
#   UfullVXA44hjjgvle9qIP3Hn5vjrnj5vTq0nT5Z2Y2M

#    AAC3NzaC1lZDI1NTE5AAAAIMZ0yYY38wDVbwxjjeWY+sGQUrHkMIthSRgAOVdAA+Z4
#    ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMZ0yYY38wDVbwxjjeWY+sGQUrHkMIthSRgAOVdAA+Z4


#   cd ~  ###### try the "<<<" redirector instead
#   mkfifo fifo
#   echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMZ0yYY38wDVbwxjjeWY+sGQUrHkMIthSRgAOVdAA+Z4" > fifo &
#   okok=$(ssh-keygen -l -f fifo)
#   rm fifo

elif [[ $1 = "-d" || $1 = "--delete" ]]; then # Delete a connection
    if [[ ! ${#} = "2" ]]; then
        echo "Enter the time stamp of the connction to delete (Example: \"p2pconnect --delete 1691422785\")."
        exit 0
    fi

    if ! [[ $2 -gt 1690000000 ]]; then
        echo "Error! Not a valid time stamp!"
        exit 1
    fi

    # Delete outbound connections
    LOCAL_PORT=$(grep -o 'LOCAL_PORT=[0-9]*' /etc/default/p2pssh@${2}* 2> /dev/null | cut -d '=' -f 2) # Get the "Local Port" that corresponds with the time stamp

    sudo rm /etc/default/p2pssh@${2}* 2> /dev/null # Remove corresponding environmental files

    sudo sed -i "/${2}/d" /etc/bitcoin.conf 2> /dev/null # Remove the comment line containing the time stamp
    sudo sed -i "/${LOCAL_PORT}/d" /etc/bitcoin.conf 2> /dev/null # Remove the "addnode=" line containing the "LOCAL_PORT"

    sudo -u bitcoin /usr/bin/bitcoin-cli -micro -datadir=/var/lib/bitcoin -conf=/etc/bitcoin.conf addnode "localhost:${LOCAL_PORT}" "remove" 2> /dev/null # Remove the node containing the "LOCAL_PORT" connection
    sudo -u bitcoin /usr/bin/bitcoin-cli -micro -datadir=/var/lib/bitcoin -conf=/etc/bitcoin.conf disconnectnode "localhost:${LOCAL_PORT}" 2> /dev/null # Force immediate disconnect

    sudo sed -i "/${2}/d" /root/.ssh/known_hosts 2> /dev/null # Remove the known host containing the time stamp

    sudo systemctl disable p2pssh@${2} --now 2> /dev/null # Disable/remove systemd services related to the time stamp
    sudo systemctl reset-failed p2pssh@${2} 2> /dev/null

    # Delete inbound connections
    sudo sed -i "/${2}/d" /home/p2p/.ssh/authorized_keys 2> /dev/null # Remove the key with a comment containing the passed "time stamp"

    # Force disconnect all users
    P2P_PIDS=$(ps -u p2p 2> /dev/null | grep sshd)
    while IFS= read -r line ; do sudo kill -9 $(echo $line | cut -d ' ' -f 1) 2> /dev/null; done <<< "$P2P_PIDS"

elif [[ $1 = "-f" || $1 = "--info" ]]; then # Get the connection parameters for this node
    if [ -f "/etc/micronode.info" ]; then
        echo ""
        sudo cat /etc/micronode.info
    else
        echo "Connection parameters have not been generated. Rerun with the -g (--generate) flag."
    fi

elif [[ $1 = "-g" || $1 = "--generate" ]]; then # Generate micronode information file (/etc/micronode.info) with connection parameters for this node
    if [ -f "/etc/micronode.info" ]; then
        echo "/etc/micronode.info file already exists"
        exit 0
    fi

    echo "Here's important information about your micronode." | sudo tee /etc/micronode.info > /dev/null
    echo "It can be used to establish secure micronode connections over ssh." | sudo tee -a /etc/micronode.info > /dev/null
    echo "" | sudo tee -a /etc/micronode.info

    echo "Hostname: $(hostname)" | sudo tee -a /etc/micronode.info
    echo "Time Stamp: $(date +%s)" | sudo tee -a /etc/micronode.info
    read -p "What is the Domain Address of this micronode? (e.g. p2p.mymicrobank.com): "; echo "Address: $REPLY" | sudo tee -a /etc/micronode.info
    read -p "What is the External SSH port for this micronode? (default 22): "; if [ -z $REPLY ]; then REPLY="22"; fi; echo "SSH Port: $REPLY" | sudo tee -a /etc/micronode.info

    echo "Local IP: $(hostname -I)" | sudo tee -a /etc/micronode.info

    if [ -z ${SSHPORT+x} ]; then SSHPORT="22"; fi
    echo "SSH Port: ${SSHPORT}" | sudo tee -a /etc/micronode.info

    if [ -z ${MICROPORT+x} ]; then MICROPORT="19333"; fi
    echo "Micro Port: ${MICROPORT}" | sudo tee -a /etc/micronode.info

    # Remove unwanted/unused host keys
    sudo rm /etc/ssh/ssh_host_dsa_key* 2> /dev/null
    sudo rm /etc/ssh/ssh_host_ecdsa_key* 2> /dev/null
    sudo rm /etc/ssh/ssh_host_rsa_key* 2> /dev/null

    echo "Host Key (Public): $(sudo cat /etc/ssh/ssh_host_ed25519_key.pub | sed 's/ root@.*//')" | sudo tee -a /etc/micronode.info
    echo "P2P Key (Public): $(sudo cat /root/.ssh/p2pkey.pub)" | sudo tee -a /etc/micronode.info

    sudo chmod 400 /etc/micronode.info

else
    $0 --help
fi