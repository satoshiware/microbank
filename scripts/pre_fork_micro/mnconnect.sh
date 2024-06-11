#!/bin/bash

# Make sure we are not running as root, but that we have sudo privileges.
if [ "$(id -u)" = "0" ]; then
   echo "This script must NOT be run as root (or with sudo)!"
   exit 1
elif [ "$(sudo -l | grep '(ALL : ALL) ALL' | wc -l)" = 0 ]; then
   echo "You do not have enough sudo privileges!"
   exit 1
fi

# See which mnconnect parameter was passed and execute accordingly
if [[ $1 = "-h" || $1 = "--help" ]]; then # Show all possible paramters
    cat << EOF
    Options:
      -i, --install     Install this script (mnconnect) in /usr/local/sbin/
      -h, --help        Display this help message and exit
      -o, --out         Make an outbound connection to the P2P Node
      -v, --view        See all configured connections and view status
      -d, --delete      Delete a connection
      -k  --key"        Show hostname and public key for this node
EOF
elif [[ $1 = "-i" || $1 = "--install" ]]; then # Install this script (mnconnect) in /usr/local/sbin
    echo "Installing this script (mnconnect) in /usr/local/sbin/"
    if [ -f /usr/local/sbin/mnconnect ]; then
        echo "This script (mnconnect) already exists in /usr/local/sbin!"
        read -p "Would you like to upgrade it? (y|n): "
        if [[ "${REPLY}" = "y" || "${REPLY}" = "Y" ]]; then
            sudo rm /usr/local/sbin/mnconnect
            cd ~; git clone https://github.com/satoshiware/microbank
            bash ~/microbank/scripts/pre_fork_micro/mnconnect.sh -i
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

    sudo cat $0 | sudo tee /usr/local/sbin/mnconnect > /dev/null
    sudo chmod +x /usr/local/sbin/mnconnect

elif [[ $1 = "-o" || $1 = "--out" ]]; then # Make an outbound connection to the p2p node
    if [[ $(ls /etc/default/p2pssh* 2> /dev/null | wc -l) -gt "0" ]]; then
        echo "There is already an outbound connection!"
        exit 1
    fi

    echo "Making outbound connection to the p2p node"
    read -p "Brief Connection Description: " CONNNAME
    read -p "Target's Host (Public) Key: " HOSTKEY
    read -p "Given Time Stamp: " TMSTAMP
    read -p "Target's Address: " TARGETADDRESS
    read -p "Target's SSH PORT (default = 22): " SSHPORT; if [ -z $SSHPORT ]; then SSHPORT="22"; fi
    read -p "Target's Bitcoin Core (micro) Port (default = 19333): " MICROPORT; if [ -z $MICROPORT ]; then MICROPORT="19333"; fi

    if ! [[ ${TMSTAMP} -gt 1690000000 ]]; then
        echo "Error! Not a valid time stamp!"
        exit 1
    fi

    # Update known_hosts
    HOSTSIG=$(ssh-keyscan -p ${SSHPORT} -H ${TARGETADDRESS})
    if [[ "${HOSTSIG}" == *"${HOSTKEY}"* ]]; then
        echo "${HOSTSIG} # ${CONNNAME}, ${TMSTAMP}, ${TARGETADDRESS}:${SSHPORT}, STRATUM" | sudo tee -a /root/.ssh/known_hosts
    else
        echo "CRITICAL ERROR: REMOTE HOST IDENTIFICATION DOES NOT MATCH GIVEN HOST KEY!!"
        exit 1
    fi

    # Create p2pssh@ p2p environment file and start its corresponding systemd service
    LOCALMICROPORT=$(python -c 'import socket; s=socket.socket(); s.bind(("", 0)); print(s.getsockname()[1]); s.close()')
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
    echo "# ${CONNNAME}, ${TMSTAMP}, ${TARGETADDRESS}:${SSHPORT}" | sudo tee -a /etc/bitcoin.conf
    echo "addnode=localhost:${LOCALMICROPORT}" | sudo tee -a /etc/bitcoin.conf

elif [[ $1 = "-d" || $1 = "--delete" ]]; then # Delete a connection
    if [[ ! ${#} = "2" ]]; then
        echo "Enter the time stamp of the connction to delete (Example: \"mnconnect --delete 1691422785\")."
        exit 0
    fi

    if ! [[ $2 -gt 1690000000 ]]; then
        echo "Error! Not a valid time stamp!"
        exit 1
    fi

    # Delete outbound connections @Level 1, 2, and 3
    LOCAL_PORT=$(grep -o 'LOCAL_PORT=[0-9]*' /etc/default/p2pssh@${2}* 2> /dev/null | cut -d '=' -f 2) # Get the "Local Port" that corresponds with the time stamp

    sudo rm /etc/default/p2pssh@${2}* 2> /dev/null # Remove corresponding environmental files

    sudo sed -i "/${2}/d" /etc/bitcoin.conf 2> /dev/null # Remove the comment line containing the time stamp
    sudo sed -i "/${LOCAL_PORT}/d" /etc/bitcoin.conf 2> /dev/null # Remove the "addnode=" line containing the "LOCAL_PORT"

    sudo -u bitcoin /usr/bin/bitcoin-cli -micro -datadir=/var/lib/bitcoin -conf=/etc/bitcoin.conf addnode "localhost:${LOCAL_PORT}" "remove" 2> /dev/null # Remove the node containing the "LOCAL_PORT" connection
    sudo -u bitcoin /usr/bin/bitcoin-cli -micro -datadir=/var/lib/bitcoin -conf=/etc/bitcoin.conf disconnectnode "localhost:${LOCAL_PORT}" 2> /dev/null # Force immediate disconnect

    sudo sed -i "/${2}/d" /root/.ssh/known_hosts 2> /dev/null # Remove the known host containing the time stamp

    sudo systemctl disable p2pssh@${2} --now 2> /dev/null # Disable/remove systemd services related to the time stamp
    sudo systemctl reset-failed p2pssh@${2} 2> /dev/null

elif [[ $1 = "-k" || $1 = "--key" ]]; then # Show hostname and public key for this node
    echo "Hostname: $(hostname)"
    echo "$(hostname) (Public) Key: $(sudo cat /root/.ssh/p2pkey.pub)"

else
    echo "Script Version 0.03"
    $0 --help
fi


###todo:
      # finish "--view"

#Update/Upgrade micronode utilities
#    cd ~; git clone https://github.com/satoshiware/microbank
#    bash ~/microbank/scripts/pre_fork_micro/mnconnect.sh -i
#    rm -rf microbank