#!/bin/bash

# Make sure we are not running as root, but that we have sudo privileges.
if [ "$(id -u)" = "0" ]; then
   echo "This script must NOT be run as root (or with sudo)!"
   exit 1
elif [ "$(sudo -l | grep '(ALL : ALL) ALL' | wc -l)" = 0 ]; then
   echo "You do not have enough sudo privileges!"
   exit 1
fi

# Universal envrionment variables
BTC=$(cat /etc/bash.bashrc | grep "alias btc=" | cut -d "\"" -f 2)

# See which p2pconnect parameter was passed and execute accordingly
if [[ $1 = "-h" || $1 = "--help" ]]; then # Show all possible paramters
    cat << EOF
    Options:
      -h, --help        Display this help message and exit
      -i, --install     Install (or upgrade) this script (p2pconnect) in /usr/local/sbin/ (/satoshiware/microbank/scripts/pre_fork_micro/p2pconnect.sh)
      -n, --in          Configure inbound cluster connection (p2p <-- wallet, p2p <-- stratum, or p2p <-- electrum)
      -p, --p2p         Make p2p inbound/outbound connections (p2p <--> p2p)
      -v, --view        See all configured connections and view status
      -d, --delete      Delete a connection: CONNECTION_ID
      -f, --info        Get the connection parameters for this node
EOF

elif [[ $1 = "-i" || $1 = "--install" ]]; then # Install (or upgrade) this script (p2pconnect) in /usr/local/sbin/ (/satoshiware/microbank/scripts/pre_fork_micro/p2pconnect.sh)
    echo "Installing this script (p2pconnect) in /usr/local/sbin/"
    if [ -f /usr/local/sbin/p2pconnect ]; then
        echo "This script (p2pconnect) already exists in /usr/local/sbin!"
        read -p "Would you like to upgrade it? (y|n): "
        if [[ "${REPLY}" = "y" || "${REPLY}" = "Y" ]]; then
            sudo rm /usr/local/sbin/p2pconnect
            cd ~; git clone https://github.com/satoshiware/microbank
            bash ~/microbank/scripts/pre_fork_micro/p2pconnect.sh -i
            rm -rf microbank
            exit 0
        else
            exit 0
        fi
    fi

    # Remove unwanted/unused host keys
    sudo rm /etc/ssh/ssh_host_dsa_key* 2> /dev/null
    sudo rm /etc/ssh/ssh_host_ecdsa_key* 2> /dev/null
    sudo rm /etc/ssh/ssh_host_rsa_key* 2> /dev/null

    sudo cat $0 | sudo tee /usr/local/sbin/p2pconnect > /dev/null
    sudo chmod +x /usr/local/sbin/p2pconnect

elif [[ $1 = "-n" || $1 = "--in" ]]; then # Configure inbound cluster connection (p2p <-- wallet, p2p <-- stratum, or p2p <-- electrum)
    echo "Let's configure an inbound connection from a wallet, stratum, or electrum node!"
    read -p "Connection Name? (e.g. \"wallet\", \"stratum\", or \"electrum\"): " CONNNAME
    read -p "What is the connecting node's public key: " PUBLICKEY
    TMSTAMP=$(date +%s)

    echo "${PUBLICKEY} # ${CONNNAME}, CONN_ID: ${TMSTAMP}, Cluster Connection" | sudo tee -a /home/p2p/.ssh/authorized_keys

elif [[ $1 = "-p" || $1 = "--p2p" ]]; then # Make p2p inbound/outbound connections (p2p <--> p2p)
    if [[ $(ls /etc/default/p2pssh*  2> /dev/null | wc -l) -ge "8" ]]; then
        echo "Error! Number of outbound connections is maxed out!"
        echo "Bitcoin Core (& microcurrency) software only supports 8 outbound connections!"
        exit 1
    fi

    echo "Configuring a (two-way) connection with another bank!"
    read -p "Connection Name: " CONNNAME
    read -p "P2P (Public) Key: " P2PKEY
    read -p "Host (Public) Key: " HOSTKEY
    read -p "Address: " BANKADDRESS
    read -p "SSH port? (default = 19022): " SSHPORT; if [ -z $SSHPORT ]; then SSHPORT="19022"; fi
    TMSTAMP=$(date +%s)

    # Update known_hosts
    HOSTSIG=$(ssh-keyscan -p ${SSHPORT} -H ${BANKADDRESS})
    if [[ "${HOSTSIG}" == *"${HOSTKEY}"* ]]; then
        echo "${HOSTSIG} # ${CONNNAME}, ${TMSTAMP}, ${BANKADDRESS}:${SSHPORT}, P2P" | sudo tee -a /root/.ssh/known_hosts
    else
        echo "CRITICAL ERROR: REMOTE HOST IDENTIFICATION DOES NOT MATCH GIVEN HOST KEY!!"
        exit 1
    fi

    # Authorize incomming connection
    echo "${P2PKEY} # ${CONNNAME}, CONN_ID: ${TMSTAMP}, P2P" | sudo tee -a /home/p2p/.ssh/authorized_keys

    # Create p2pssh@ environment file and start its corresponding systemd service
    LOCALMICROPORT=$(python3 -c 'import socket; s=socket.socket(); s.bind(("", 0)); print(s.getsockname()[1]); s.close()')
    cat << EOF | sudo tee /etc/default/p2pssh@${TMSTAMP}
# ${CONNNAME}
LOCAL_PORT=${LOCALMICROPORT}
FORWARD_PORT=19333
TARGET=${TARGETADDRESS}
TARGET_PORT=${SSHPORT}
EOF
    sudo systemctl enable p2pssh@${TMSTAMP} --now

    # Add the outbound connection to Bitcoin Core (micro) and update bitcoin.conf to be reestablish automatically upon restart or boot up
    sudo -u bitcoin /usr/bin/bitcoin-cli -micro -datadir=/var/lib/bitcoin -conf=/etc/bitcoin.conf addnode localhost:${LOCALMICROPORT} "add"
    echo "# ${CONNNAME}, CONN_ID: ${TMSTAMP}, ${TARGETADDRESS}:${SSHPORT}" | sudo tee -a /etc/bitcoin.conf # Add comment to the bitcoin.conf file
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

elif [[ $1 = "-d" || $1 = "--delete" ]]; then # Delete a connection: CONNECTION_ID
    if [[ ! ${#} = "2" ]]; then
        echo "Enter the Connection ID to delete (Example: \"mnconnect --delete 1691422785\")."
        exit 0
    fi

    # Delete outbound connection
    LOCAL_PORT=$(grep -o 'LOCAL_PORT=[0-9]*' /etc/default/p2pssh@${2}* 2> /dev/null | cut -d '=' -f 2) # Get the "Local Port" that corresponds with the time stamp

    sudo rm /etc/default/p2pssh@${2}* 2> /dev/null # Remove corresponding environmental files

    sudo sed -i "/${2}/d" /etc/bitcoin.conf 2> /dev/null # Remove the comment line containing the time stamp
    sudo sed -i "/${LOCAL_PORT}/d" /etc/bitcoin.conf 2> /dev/null # Remove the "addnode=" line containing the "LOCAL_PORT"

    sudo -u bitcoin /usr/bin/bitcoin-cli -micro -datadir=/var/lib/bitcoin -conf=/etc/bitcoin.conf addnode "localhost:${LOCAL_PORT}" "remove" 2> /dev/null # Remove the node containing the "LOCAL_PORT" connection
    sudo -u bitcoin /usr/bin/bitcoin-cli -micro -datadir=/var/lib/bitcoin -conf=/etc/bitcoin.conf disconnectnode "localhost:${LOCAL_PORT}" 2> /dev/null # Force immediate disconnect

    sudo sed -i "/${2}/d" /root/.ssh/known_hosts 2> /dev/null # Remove the known host containing the time stamp

    # Disable/remove systemd services related to the time stamp
    sudo systemctl disable p2pssh@${2} --now 2> /dev/null
    sudo systemctl reset-failed p2pssh@${2} 2> /dev/null

    # Delete inbound connection
    sudo sed -i "/${2}/d" /home/p2p/.ssh/authorized_keys 2> /dev/null

    # Force disconnect all users
    P2P_PIDS=$(ps -u p2p 2> /dev/null | grep sshd)
    while IFS= read -r line ; do sudo kill -9 $(echo $line | cut -d ' ' -f 1) 2> /dev/null; done <<< "$P2P_PIDS"

elif [[ $1 = "-f" || $1 = "--info" ]]; then # Get the connection parameters for this node
    echo "Hostname: $(hostname)" | sudo tee -a /etc/micronode.info
    echo "Local IP: $(hostname -I)" | sudo tee -a /etc/micronode.info

    echo "Host Key (Public): $(sudo cat /etc/ssh/ssh_host_ed25519_key.pub | sed 's/ root@.*//')"
    echo "P2P Key (Public): $(sudo cat /root/.ssh/p2pkey.pub)"

else
    $0 --help
    echo "Script Version 0.08"
fi