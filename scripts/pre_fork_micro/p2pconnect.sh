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
      --install         Install (or upgrade) this script (p2pconnect) in /usr/local/sbin/ (/satoshiware/microbank/scripts/pre_fork_micro/p2pconnect.sh)
      --cron            (Re)Create cronjob to run --status routine every 6 hours: RECIPIENTS_NAME  EMAIL
      --status          Show/Verify status of all connections (in and out): RECIPIENTS_NAME  EMAIL
                            Sends email if there are any inactive/disconnected nodes (requires send_messages to be configured).
                            Note: If any inbound connections have become inactive, the "Dynamic DNS" script will be called.
      -n, --in          Configure inbound cluster connection (p2p <-- wallet, p2p <-- stratum, or p2p <-- electrum)
      -p, --p2p         Make p2p inbound/outbound connections (p2p <--> p2p)
      -v, --view        See all configured connections
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

elif [[ $1 = "--cron" ]]; then # (Re)Create cronjob to run --status routine every 6 hours: RECIPIENTS_NAME  EMAIL
    NAME=$2; EMAIL=$3
    if [[ -z $NAME || -z $EMAIL ]]; then
        echo "Error! Insufficient Parameters!"
        exit 1
    fi

    # Add Cron Job to run the --status routine every 6 hours. Run "crontab -e" as $USER to see all its cron jobs.
    (crontab -l | grep -v -F "/usr/local/sbin/p2pconnect --status" ; echo "0 */6 * * * /bin/bash -lc \"/usr/local/sbin/p2pconnect --status $NAME $EMAIL\"" ) | crontab -

elif [[ $1 = "--status" ]]; then # Show/Verify status of all connections (in and out): RECIPIENTS_NAME  EMAIL. Sends email if there are any inactive/disconnected nodes (requires send_messages to be configured). Note: If any inbound connections have become inactive, the "Dynamic DNS" script will be called.
    # Get/Show network info
    networkinfo=$($BTC getnetworkinfo)
    NET_ACTIVE=$(echo $networkinfo | jq -r '.networkactive')
    IN_QTY=$(echo $networkinfo | jq -r '.connections_in')
    OUT_QTY=$(echo $networkinfo | jq -r '.connections_out')
    echo "RPC \"getnetworkinfo\":"; echo "------------------------------------------------------------------"
    echo -n "    Network Active: "; echo $NET_ACTIVE
    echo -n "    In Connection(s): "; echo $IN_QTY
    echo -n "    Out Connection(s): "; echo $OUT_QTY

    # Show status of each configured incomming connection
    echo ""; echo "Configured Incomming Connection(s):"; echo "------------------------------------------------------------------"
    readarray -t incomming <<< $(sudo cat /home/p2p/.ssh/authorized_keys | grep . | grep "\S")
    for line in "${incomming[@]}"; do
        hash=$(echo "$line" | grep -Go 'SHA256(Base64): .*' | cut -d " " -f 2)
        port=$(journalctl -u ssh.service | grep $hash | tail -n 1 | grep -Go 'port.*ssh2' | cut -d " " -f 2)
        connected=$(ss -t -a | grep "^.*:ssh .*:$port\s\+$") # If line returned then the incomming connection is active!
        echo -n "   "; echo $line | cut -d "#" -f 2
        if [[ -z $connected ]]; then
            echo "    Connected: False"
        else
            echo "    Connected: True"
        fi
        echo ""
    done

    # Loop through each added node (i.e. local port)
    echo ""; echo "Outbound: Added Node Info (RPC \"getaddednodeinfo\")"; echo "------------------------------------------------------------------"
    info=$($BTC getaddednodeinfo); length=$(echo -n $info | jq length)
    for (( i=0; i<$length; i++ )); do
        echo -n "    "; echo -n $info | jq -j -r ".[$i].addednode"; echo -n "        Connected: "; echo $info | jq ".[$i].connected"
    done

    # Show the p2pssh (autossh) process for each outgoing connection
    echo ""; echo "Outbound: View each p2pssh@* .env file and process status (/etc/default/p2pssh@*)"; echo "------------------------------------------------------------------"
    p2pssh=($(sudo ls /etc/default/p2pssh* 2> /dev/null))
    for i in "${p2pssh[@]}"; do
        echo "#########$(sudo head -n 1 $i)    $(sudo sed '2!d' $i)    $(sudo sed '3!d' $i)    $(sudo tail -n 1 $i) ########"
        sudo systemctl status $(echo $i | cut -d "/" -f 4); echo ""
    done

    # Test for any failed connection and respond accordingly
    CONF_IN_QTY=$(sudo cat /home/p2p/.ssh/authorized_keys | grep . | grep "\S" | wc -l)
    CONF_OUT_QTY=$(sudo cat /root/.ssh/known_hosts | grep . | grep "\S" | wc -l)
    if [[ ! $NET_ACTIVE == "true" || $CONF_IN_QTY -ne $IN_QTY || $CONF_OUT_QTY -gt $OUT_QTY ]]; then
        NAME=$2; EMAIL=$3
        if [[ $CONF_IN_QTY -ne $IN_QTY ]]; then echo ""; echo "Running Dynamic DNS"; dynamic_dns --update $NAME $EMAIL > /dev/null; fi # Run Dynamic DNS if there's a mismatch between configured in' connections and auctual in' connections.

        if ! [[ -z $NAME || -z $EMAIL ]]; then
            MESSAGE=${MESSAGE//$'\n'/'<br>'}
            MESSAGE=${MESSAGE// /\&nbsp;}
            send_messages --email $NAME $EMAIL "Micro Node Connection Issues" $MESSAGE
        fi
    fi

elif [[ $1 = "-n" || $1 = "--in" ]]; then # Configure inbound cluster connection (p2p <-- wallet, p2p <-- stratum, or p2p <-- electrum)
    echo "Let's configure an inbound connection from a wallet, stratum, or electrum node!"
    read -p "Connection Name? (e.g. \"wallet\", \"stratum\", or \"electrum\"): " CONNNAME
    read -p "What is the connecting node's public key: " PUBLICKEY
    TMSTAMP=$(date +%s)

    echo $PUBLICKEY > /tmp/cluster-key-${TMSTAMP}.pub
    BASE64=$(ssh-keygen -lf /tmp/cluster-key-${TMSTAMP}.pub | cut -d ':' -f 2 | cut -d ' ' -f 1)
    rm /tmp/cluster-key-${TMSTAMP}.pub

    echo "${PUBLICKEY} # ${CONNNAME}, CONN_ID: ${TMSTAMP}, Cluster Connection, SHA256(Base64): ${BASE64}" | sudo tee -a /home/p2p/.ssh/authorized_keys

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
    echo $P2PKEY > /tmp/p2p-key-${TMSTAMP}.pub
    BASE64=$(ssh-keygen -lf /tmp/p2p-key-${TMSTAMP}.pub | cut -d ':' -f 2 | cut -d ' ' -f 1)
    rm /tmp/p2p-key-${TMSTAMP}.pub

    echo "${P2PKEY} # ${CONNNAME}, CONN_ID: ${TMSTAMP}, P2P, SHA256(Base64): ${BASE64}" | sudo tee -a /home/p2p/.ssh/authorized_keys

    # Create p2pssh@ environment file and start its corresponding systemd service
    LOCALMICROPORT=$(python3 -c 'import socket; s=socket.socket(); s.bind(("", 0)); print(s.getsockname()[1]); s.close()')
    cat << EOF | sudo tee /etc/default/p2pssh@${TMSTAMP}
# ${CONNNAME}
LOCAL_PORT=${LOCALMICROPORT}
TARGET=${TARGETADDRESS}
TARGET_PORT=${SSHPORT}
EOF
    sudo systemctl enable p2pssh@${TMSTAMP} --now

    # Add the outbound connection to Bitcoin Core (micro) and update bitcoin.conf to be reestablish automatically upon restart or boot up
    sudo -u bitcoin /usr/bin/bitcoin-cli -micro -datadir=/var/lib/bitcoin -conf=/etc/bitcoin.conf addnode localhost:${LOCALMICROPORT} "add"
    echo "# ${CONNNAME}, CONN_ID: ${TMSTAMP}, ${TARGETADDRESS}:${SSHPORT}" | sudo tee -a /etc/bitcoin.conf # Add comment to the bitcoin.conf file
    echo "addnode=localhost:${LOCALMICROPORT}" | sudo tee -a /etc/bitcoin.conf # Add connection

elif [[ $1 = "-v" || $1 = "--view" ]]; then # See all configured connections
    # Show the contents of the Authorized Keys file (inbound)
    echo "Inbound: Authorized Keys File (/home/p2p/.ssh/authorized_keys)"; echo "------------------------------------------------------------------"; sudo cat /home/p2p/.ssh/authorized_keys

    # Show the contents of the Bitcoin configuration file
    echo ""; echo "Outbound: Bitcoin Configuration File (/etc/bitcoin.conf)"; echo "------------------------------------------------------------------"; sudo cat /etc/bitcoin.conf

    # Show the contents of the Known Hosts file (outbound)
    echo ""; echo "Outbound: Known Hosts File (/root/.ssh/known_hosts)"; echo "------------------------------------------------------------------"; sudo cat /root/.ssh/known_hosts

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

    echo "This Host Key (Public): $(sudo cat /etc/ssh/ssh_host_ed25519_key.pub | sed 's/ root@.*//')"
    echo "This P2P Key (Public): $(sudo cat /root/.ssh/p2pkey.pub)"

else
    $0 --help
    echo "Script Version 0.181"
fi
