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

# See which mnconnect parameter was passed and execute accordingly
if [[ $1 = "-h" || $1 = "--help" ]]; then # Show all possible paramters
    cat << EOF
    Options:
      -h, --help        Display this help message and exit
      -i, --install     Install (or upgrade) this script (mnconnect) in /usr/local/sbin/ (Repository: /satoshiware/microbank/scripts/pre_fork_micro/mnconnect.sh)
      -o, --out         Make an outbound outbound connection to the P2P Node
      -v, --view        See configured connection and status
      -d, --delete      Delete a connection
      -k  --key         Show hostname and public key for this node
EOF
elif [[ $1 = "-i" || $1 = "--install" ]]; then # Install (or upgrade) this script (mnconnect) in /usr/local/sbin/ (/satoshiware/microbank/scripts/pre_fork_micro/mnconnect.sh)
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

    echo "Making outbound connection to the P2P Node"
    read -p "Connection Name: " CONNNAME
    read -p "Target's Host (Public) Key: " HOSTKEY
    read -p "Target's Address: " TARGETADDRESS

    TMSTAMP=$(date +%s)

    # Update known_hosts
    HOSTSIG=$(ssh-keyscan -p 22 -H ${TARGETADDRESS})
    if [[ "${HOSTSIG}" == *"${HOSTKEY}"* ]]; then
        echo "${HOSTSIG} # ${CONNNAME}, CONN_ID: ${TMSTAMP}, ${TARGETADDRESS}, STRATUM" | sudo tee -a /root/.ssh/known_hosts
    else
        echo "CRITICAL ERROR: REMOTE HOST IDENTIFICATION DOES NOT MATCH GIVEN HOST KEY!!"
        exit 1
    fi

    # Create p2pssh@ p2p environment file and start its corresponding systemd service
    LOCALMICROPORT=$(python -c 'import socket; s=socket.socket(); s.bind(("", 0)); print(s.getsockname()[1]); s.close()')
    cat << EOF | sudo tee /etc/default/p2pssh@${TMSTAMP}
# ${CONNNAME}
LOCAL_PORT=${LOCALMICROPORT}
FORWARD_PORT=19333
TARGET=${TARGETADDRESS}
TARGET_PORT=22
EOF
    sudo systemctl enable p2pssh@${TMSTAMP} --now

    # Add the outbound connection to Bitcoin Core (micro) and update bitcoin.conf to be reestablish automatically upon restart or boot up
    sudo -u bitcoin /usr/bin/bitcoin-cli -micro -datadir=/var/lib/bitcoin -conf=/etc/bitcoin.conf addnode localhost:${LOCALMICROPORT} "add"
    echo "# ${CONNNAME}, CONN_ID: ${TMSTAMP}, ${TARGETADDRESS}" | sudo tee -a /etc/bitcoin.conf
    echo "addnode=localhost:${LOCALMICROPORT}" | sudo tee -a /etc/bitcoin.conf

elif [[ $1 = "-v" || $1 = "--view" ]]; then # See configured outbound connection and status
    if [[ $(ls /etc/default/p2pssh* 2> /dev/null | wc -l) -eq "0" ]]; then
        echo "There is no outbound connection!"
        exit 1
    fi

    echo ""; echo "Connection Name (p2pssh@$CONN_ID):"
    ls /etc/default/p2pssh* -all

    echo ""; echo "This Node Status:"
    if [[ $($BTC getaddednodeinfo | jq '.[0] | .connected') == "true" ]]; then
        echo "    YES! You are CONNECTED!"
    else
        echo "    NO! You are NOT connected!"
    fi

    echo ""; echo "AutoSSH Status:"
    systemctl status p2pssh@$(ls /etc/default/p2pssh* | cut -d '@' -f 2 | head -n 1)

    echo ""; echo "Bitcoin Configuration File:"
    sudo cat /etc/bitcoin.conf; echo ""

elif [[ $1 = "-d" || $1 = "--delete" ]]; then # Delete a connection
    if [[ ! ${#} = "2" ]]; then
        echo "Enter the Connection ID to delete (Example: \"mnconnect --delete 1691422785\")."
        exit 0
    fi

    LOCAL_PORT=$(grep -o 'LOCAL_PORT=[0-9]*' /etc/default/p2pssh@${2}* 2> /dev/null | cut -d '=' -f 2) # Get the "Local Port" that corresponds with the time stamp

    sudo rm /etc/default/p2pssh@${2}* 2> /dev/null # Remove corresponding environmental files

    sudo sed -i "/${2}/d" /root/.ssh/known_hosts 2> /dev/null # Remove the comment line containing the time stamp from the known_hosts
    sudo sed -i "/${2}/d" /etc/bitcoin.conf 2> /dev/null # Remove the comment line containing the time stamp from the bitcoin.conf
    sudo sed -i "/${LOCAL_PORT}/d" /etc/bitcoin.conf 2> /dev/null # Remove the "addnode=" line containing the "LOCAL_PORT"

    sudo -u bitcoin /usr/bin/bitcoin-cli -micro -datadir=/var/lib/bitcoin -conf=/etc/bitcoin.conf addnode "localhost:${LOCAL_PORT}" "remove" 2> /dev/null # Remove the node containing the "LOCAL_PORT" connection
    sudo -u bitcoin /usr/bin/bitcoin-cli -micro -datadir=/var/lib/bitcoin -conf=/etc/bitcoin.conf disconnectnode "localhost:${LOCAL_PORT}" 2> /dev/null # Force immediate disconnect

    sudo systemctl disable p2pssh@${2} --now 2> /dev/null # Disable/remove systemd services related to the time stamp
    sudo systemctl reset-failed p2pssh@${2} 2> /dev/null

elif [[ $1 = "-k" || $1 = "--key" ]]; then # Show hostname and public key for this node
    echo "Hostname: $(hostname)"
    echo "$(hostname) (Public) Key: $(sudo cat /root/.ssh/p2pkey.pub)"

else
    $0 --help
    echo "Script Version 0.032"
fi