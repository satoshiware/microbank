#!/bin/bash

# Make sure we are not running as root, but that we have sudo privileges.
if [ "$(id -u)" = "0" ]; then
   echo "This script must NOT be run as root (or with sudo)!"
   exit 1
elif [ "$(sudo -l | grep '(ALL : ALL) ALL' | wc -l)" = 0 ]; then
   echo "You do not have enough sudo privileges!"
   exit 1
fi

# Get the level for this node/hub
NDLVL=$(sudo cat /etc/nodelevel)
if [[ "${NDLVL}" != "1" && "${NDLVL}" != "2" && "${NDLVL}" != "3" ]]; then
    echo "Error: The level of this hub/node is not set properly (/etc/nodelevel)!"
    exit 1
fi

# Install this script (mnconnect) in /usr/local/sbin
if [[ $1 = "-i" || $1 = "--install" ]]; then
    echo "Installing this script (mnconnect) in /usr/local/sbin/"
    if [ ! -f /usr/local/sbin/mnconnect ]; then
        sudo cat $0 | sudo tee /usr/local/sbin/mnconnect > /dev/null
        sudo chmod +x /usr/local/sbin/mnconnect
    else
        echo "\"mnconnect\" already exists in /usr/local/sbin!"
        read -p "Would you like to uninstall it? (y|n): "
        if [[ "${REPLY}" = "y" || "${REPLY}" = "Y" ]]; then
            sudo rm /usr/local/sbin/mnconnect
        fi
    fi
    exit 0
fi

# Make sure this script is installed
if [ ! -f /usr/local/sbin/mnconnect ]; then
    echo "Error: this script is not yet installed to \"/usr/local/sbin/mnconnect\"!"
    echo "Rerun this script with the \"-i\" or \"--install\" parameter!"
    exit 1
fi

# See which mnconnect parameter was passed and execute accordingly
if [[ $1 = "-h" || $1 = "--help" ]]; then # Configure inbound mining connection (level 1 <-- miners)
    cat << EOF
    Options:
      -i, --install     Install this script (mnconnect) in /usr/local/sbin/
      -h, --help        Display this help message and exit
      -m, --mining      Configure inbound mining connection (level 1 <-- miners)
      -s, --stratum     Make p2p and stratum outbound connections (level 1 --> 2 or 2 --> 3)
      -n, --in          Configure inbound connection (Level 3 <-- 2 or 2 <-- 1)
      -p, --p2p         Make p2p inbound/outbound connections (level 3 <--> 3)
      -r, --remote      Configure inbound connection for a level 3 remote mining operation
      -y, --priority    Sets the priorities of the stratum proxy connections for a level 2 node/hub
      -v, --view        See all configured connections and view status
      -d, --delete      Delete a connection
      -f, --info        Get the connection parameters for this node
EOF
elif [[ $1 = "-m" || $1 = "--mining" ]]; then # Configure inbound mining connection (level 1 <-- miners)
    if [ ${NDLVL} != "1" ]; then
        echo "This option is for node/hub level 1 only!"
        echo "This node is configured for level ${NDLVL}!"
        exit 1
    fi

    echo "Configuring to allow mining inbound connection..."
    read -p "Connection Name: " CONNNAME
    read -p "Stratum (Public) Key: " STRATKEY
    read -p "Given Time Stamp: " TMSTAMP

    echo "${STRATKEY} # ${CONNNAME}, ${TMSTAMP}" | sudo tee -a /home/stratum/.ssh/authorized_keys

elif [[ $1 = "-s" || $1 = "--stratum" ]]; then # Make p2p and stratum outbound connections (level 1 --> 2 or 2 --> 3)
    if [[ ${NDLVL} != "1" && ${NDLVL} != "2" ]]; then
        echo "This option is for node/hub level 1 & 2 only!"
        echo "This node/hub is configured for level ${NDLVL}!"
        exit 1
    elif [[ ${NDLVL} = "1" && $(ls /etc/default/p2pssh* 2> /dev/null | wc -l) -gt "0" ]]; then
        echo "There is already an outbound connection!"
        exit 1
    elif [[ ${NDLVL} = "2" && $(ls /etc/default/p2pssh* 2> /dev/null | wc -l) -gt "4" ]]; then # Why 4? Because there is a max of 3 Stratum and 3 P2P where the total number of connections is always an even number.
        echo "Number of outbound connections are maxed out!"
        exit 1
    fi

    echo "Making p2p and stratum outbound connections to a level $(if [ ${NDLVL} = "1" ]; then echo '2'; else echo '3'; fi) node/hub..."
    read -p "Connection Name: " CONNNAME
    read -p "Target's Host (Public) Key: " HOSTKEY
    read -p "Given Time Stamp: " TMSTAMP
    read -p "Target's Address: " TARGETADDRESS
    read -p "Target's SSH PORT (default = 22): " SSHPORT; if [ -z $SSHPORT ]; then SSHPORT="22"; fi
    read -p "Target's Bitcoin Core (micro) Port (default = 19333): " MICROPORT; if [ -z $MICROPORT ]; then MICROPORT="19333"; fi
    read -p "Target's Stratum Port (default = 3333): " STRATUMPORT; if [ -z $STRATUMPORT ]; then STRATUMPORT="3333"; fi

    # update known_hosts
    echo "${HOSTKEY} # ${CONNNAME}, ${TMSTAMP}, ${TARGETADDRESS}:${SSHPORT}, STRATUM" | sudo tee -a /root/.ssh/known_hosts

    # create p2pssh@ stratum environment file and start its corresponding systemd service
    cat << EOF | sudo tee /etc/default/p2pssh@${TMSTAMP}-stratum
# ${CONNNAME}
LOCAL_PORT=$(if [ "${NDLVL}" = "1" ]; then sudo cat /etc/stratumport; fi)
FORWARD_PORT=${STRATUMPORT}
TARGET=${TARGETADDRESS}
TARGET_PORT=${SSHPORT}
EOF
    sudo systemctl enable p2pssh@${TMSTAMP}-stratum # Level 2 stratum outbound connections will note be started until their priorities are configured
    if [ "${NDLVL}" = "1" ]; then sudo systemctl start p2pssh@${TMSTAMP}-stratum; fi # Start Level 1 stratum outbound connection now

    # create p2pssh@ p2p environment file and start its corresponding systemd service
    LOCALMICROPORT=$(python -c 'import socket; s=socket.socket(); s.bind(("", 0)); print(s.getsockname()[1]); s.close()')
    cat << EOF | sudo tee /etc/default/p2pssh@${TMSTAMP}-p2p
# ${CONNNAME}
LOCAL_PORT=${LOCALMICROPORT}
FORWARD_PORT=${MICROPORT}
TARGET=${TARGETADDRESS}
TARGET_PORT=${SSHPORT}
EOF
    sudo systemctl enable p2pssh@${TMSTAMP}-p2p --now

    # Add the outbound connection to Bitcoin Core (micro) and update bitcoin.conf to be reestablish automatically upon restart or boot up
    sudo -u bitcoin /usr/bin/bitcoin-cli -micro -datadir=/var/lib/bitcoin -conf=/etc/bitcoin.conf addnode localhost:${LOCALMICROPORT} "add"
    echo "# ${CONNNAME}, ${TMSTAMP}, ${TARGETADDRESS}:${SSHPORT}" | sudo tee -a /etc/bitcoin.conf
    echo "addnode=localhost:${LOCALMICROPORT}" | sudo tee -a /etc/bitcoin.conf

    # Set the priority for the new stratum proxy connection (level 2 only)
    if [ "${NDLVL}" = "2" ]; then
        echo ""
        echo "The new stratum proxy service connection p2pssh@${TMSTAMP}-stratum has been enabled, but NOT started."
        echo "It will not run properly until a priority is set via the \"mnconnect --priority\" command."
        echo "Let's configure that new priority right now!"; read -p "Press enter to continue ..."
        mnconnect --priority
    fi

elif [[ $1 = "-n" || $1 = "--in" ]]; then # Configure inbound connection (Level 3 <-- 2 or 2 <-- 1)
    if [[ ${NDLVL} != "2" && ${NDLVL} != "3" ]]; then
        echo "This option is for node/hub level 2 & 3 only!"
        echo "This node/hub is configured for level ${NDLVL}!"
        exit 1
    fi

    echo "Configuring to allow inbound connection from a level $(if [ ${NDLVL} = "2" ]; then echo '1'; else echo '2'; fi) node/hub..."
    read -p "Connection Name: " CONNNAME
    read -p "P2P (Public) Key: " P2PKEY
    read -p "Given Time Stamp: " TMSTAMP

    echo "${P2PKEY} # ${CONNNAME}, ${TMSTAMP}$(if [ "${NDLVL}" = "3" ]; then echo ', LVL2'; fi)" | sudo tee -a /home/p2p/.ssh/authorized_keys

elif [[ $1 = "-p" || $1 = "--p2p" ]]; then # Make p2p inbound/outbound connections (level 3 <--> 3)
    if [ ${NDLVL} != "3" ]; then
        echo "This option is for node/hub level 3 only!"
        echo "This node/hub is configured for level ${NDLVL}!"
        exit 1
    elif [[ $(ls /etc/default/p2pssh*  2> /dev/null | wc -l) -ge "8" ]]; then
        echo "Number of outbound connections is maxed out!"
        echo "Bitcoin Core only supports 8 outbound connections!"
        exit 1
    fi

    echo "Configuring to allow inbound connection from a level 3 node/hub..."
    read -p "Connection Name: " CONNNAME
    read -p "P2P (Public) Key: " P2PKEY
    read -p "Given Time Stamp: " TMSTAMP

    echo "${P2PKEY} # ${CONNNAME}, ${TMSTAMP}, P2P" | sudo tee -a /home/p2p/.ssh/authorized_keys

    echo "Making p2p outbound connection to a level 3 node/hub..."
    read -p "Target's Host (Public) Key: " HOSTKEY
    read -p "Target's Address: " TARGETADDRESS
    read -p "Target's SSH PORT (default = 22): " SSHPORT; if [ -z $SSHPORT ]; then SSHPORT="22"; fi
    read -p "Target's Bitcoin Core (micro) Port (default = 19333): " MICROPORT; if [ -z $MICROPORT ]; then MICROPORT="19333"; fi

    # update known_hosts
    echo "${HOSTKEY} # ${CONNNAME}, ${TMSTAMP}, ${TARGETADDRESS}:${SSHPORT}, P2P" | sudo tee -a /root/.ssh/known_hosts

    # create p2pssh@ level 3 p2p environment file and start its corresponding systemd service
    LOCALMICROPORT=$(python -c 'import socket; s=socket.socket(); s.bind(("", 0)); print(s.getsockname()[1]); s.close()')
    cat << EOF | sudo tee /etc/default/p2pssh@${TMSTAMP}-lvl3
# ${CONNNAME}
LOCAL_PORT=${LOCALMICROPORT}
FORWARD_PORT=${MICROPORT}
TARGET=${TARGETADDRESS}
TARGET_PORT=${SSHPORT}
EOF
    sudo systemctl enable p2pssh@${TMSTAMP}-lvl3 --now

    # Add the outbound connection to Bitcoin Core (micro) and update bitcoin.conf to be reestablish automatically upon restart or boot up
    sudo -u bitcoin /usr/bin/bitcoin-cli -micro -datadir=/var/lib/bitcoin -conf=/etc/bitcoin.conf addnode localhost:${LOCALMICROPORT} "add"
    echo "# ${CONNNAME}, ${TMSTAMP}, ${TARGETADDRESS}:${SSHPORT}" | sudo tee -a /etc/bitcoin.conf
    echo "addnode=localhost:${LOCALMICROPORT}" | sudo tee -a /etc/bitcoin.conf

elif [[ $1 = "-r" || $1 = "--remote" ]]; then # Configure inbound connection for a level 3 remote mining operation
    if [ ${NDLVL} != "3" ]; then
        echo "This option is for node/hub level 3 only!"
        echo "This node/hub is configured for level ${NDLVL}!"
        exit 1
    fi

    echo "Configuring inbound connection for a level 3 remote mining operation..."
    read -p "Connection Name: " CONNNAME
    read -p "P2P (Public) Key: " P2PKEY
    read -p "Given Time Stamp: " TMSTAMP

    echo "${P2PKEY} # ${CONNNAME}, ${TMSTAMP}, REMOTE" | sudo tee -a /home/p2p/.ssh/authorized_keys

elif [[ $1 = "-y" || $1 = "--priority" ]]; then # Sets the priorities of the stratum proxy connections for a level 2 node/hub
    if [ ${NDLVL} != "2" ]; then
        echo "This option is for node/hub level 2 only!"
        echo "This node/hub is configured for level ${NDLVL}!"
        exit 1
    elif [ $(ls /etc/default/p2pssh*-stratum 2> /dev/null | wc -l) = "0" ]; then
        echo "There are no stratum proxy connections to prioritize!"
        exit 1
    fi

    readarray -t PROXIES < <(ls /etc/default/p2pssh*-stratum) # Make an array with all the Stratum Environment file locations
    if [ "${2}" = "set" ]; then # Recursion call with parameter $2 = "set"
        echo "Ok, now let's set new priorities for each stratum proxy connection for this level 2 node/hub..."
        echo "    !!!!! WARNING! EACH CONNECTION MUST HAVE A UNIQUE PRIORITY! !!!!!"; echo ""
    else
        echo ""; echo "Current proxy connection(s) with their respective prioritie(s):"
    fi

    PROXPORTS=() # This array holds the ports; one for each proxy
    PROXPORTS[1]=$(sudo cat /etc/ckproxy.conf | jq '.proxy[0] .url' | cut -d ':' -f 2 | sed 's/\"//g')
    PROXPORTS[2]=$(sudo cat /etc/ckproxy.conf | jq '.proxy[1] .url' | cut -d ':' -f 2 | sed 's/\"//g')
    PROXPORTS[3]=$(sudo cat /etc/ckproxy.conf | jq '.proxy[2] .url' | cut -d ':' -f 2 | sed 's/\"//g')
    for i in "${PROXIES[@]}"; do # List the details of each proxy connection; loop also used to set the priority on second pass (with $2 = "set")
        PROXYNAME=$(cat "$i" | grep "#" | sed 's/#//g' | sed 's/ //g')
        PORTPRIORITY=$(cat "$i" | grep "LOCAL_PORT" | cut -d '=' -f 2 | sed 's/ //g')
        TARGETADDRESS=$(cat "$i" | grep "TARGET=" | cut -d '=' -f 2 | sed 's/ //g')
        TARGETPORT=$(cat "$i" | grep "TARGET_PORT" | cut -d '=' -f 2 | sed 's/ //g')
        TIMESTAMP=$(echo "$i" | cut -d '@' -f 2 | cut -d '-' -f 1)

        if [[ "${PORTPRIORITY}" == *"${PROXPORTS[1]}"* ]]; then
            PORTPRIORITY="PRIORITY = 1 (High Priority)"
        elif [[ "${PORTPRIORITY}" == *"${PROXPORTS[2]}"* ]]; then
            PORTPRIORITY="PRIORITY = 2 (Medium Priority)"
        elif [[ "${PORTPRIORITY}" == *"${PROXPORTS[3]}"* ]]; then
            PORTPRIORITY="PRIORITY = 3 (Low Priority)"
        else
            PORTPRIORITY="PRIORITY = NULL (Priority Not Set)"
        fi

        if [ "${2}" = "set" ]; then
            read -p "New priority for \"${PROXYNAME}, ${TARGETADDRESS}:${TARGETPORT}, ${TIMESTAMP}\" (1, 2, or 3): "
            sudo sed -i "s/.*LOCAL_PORT.*/LOCAL_PORT=${PROXPORTS[${REPLY}]}/g" $i
        else
            echo "    ${PROXYNAME}, ${TARGETADDRESS}:${TARGETPORT}, ${TIMESTAMP}, ${PORTPRIORITY}"
        fi
    done

    if [ "${2}" != "set" ]; then
        echo ""
        read -p "Would you like to continue with resetting the priorities? (y|Y): "
        if [[ "${REPLY}" = "y" || "${REPLY}" = "Y" ]]; then
            echo ""; echo "Stopping all stratum proxy autossh systemd connection(s)"
            for i in "${PROXIES[@]}"; do sudo systemctl stop $(echo "$i" | sed 's/\/etc\/default\///g'); done

            echo "Setting all priorities to NULL"; echo ""
            for i in "${PROXIES[@]}"; do sudo sed -i "s/.*LOCAL_PORT.*/LOCAL_PORT=/g" $i; done
            mnconnect --priority set
        fi
    else
        # Get the ports from the stratum proxy autossh systemd environment files
        STPRXPORTS=(); i=0
        for j in "${PROXIES[@]}"; do
            STPRXPORTS[i]=$(cat "$j" | grep "LOCAL_PORT" | cut -d '=' -f 2 | sed 's/ //g')
            let i++
        done

        # Check to see if any of the local stratum proxy ports (i.e. priorities) are the same
        PRIFAILURE="false"
        if [ ${#STPRXPORTS[@]} = "2" ]; then
            if [ "${STPRXPORTS[0]}" = "${STPRXPORTS[1]}" ]; then PRIFAILURE="true"; fi
        elif [ ${#STPRXPORTS[@]} = "3" ]; then
            if [[ "${STPRXPORTS[0]}" == "${STPRXPORTS[1]}" || "${STPRXPORTS[0]}" == "${STPRXPORTS[2]}" || "${STPRXPORTS[1]}" == "${STPRXPORTS[2]}" ]]; then PRIFAILURE="true"; fi
        fi

        # Check to see if any local stratum proxy ports (i.e. priorities) were not set properly (e.g. set to NULL)
        for i in "${STPRXPORTS[@]}"; do
            if [ -z "${i}" ]; then PRIFAILURE="true"; fi
        done

		# Check to see if there were any failures with the user's inputs
		if [ "${PRIFAILURE}" = "true" ]; then
			echo ""; echo "Error! Invalid priorities. Try again."
			
			echo "Setting all priorities to NULL"; echo ""
            for i in "${PROXIES[@]}"; do sudo sed -i "s/.*LOCAL_PORT.*/LOCAL_PORT=/g" $i; done
			exit 1
		fi

        echo ""; echo "(Re)starting stratum proxy autossh systemd connection(s)"
        for i in "${PROXIES[@]}"; do sudo systemctl start $(echo "$i" | sed 's/\/etc\/default\///g'); done
    fi

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

elif [[ $1 = "-d" || $1 = "--delete" ]]; then # Delete a connection ############## this comment ############ should pass a parameter or show connections.

    #####################todo
#   Add input checking on the time stamp everywhere. we are going to use that to delete
    ####################### needs work #######################################
    echo "you made it buddy to --delete"

elif [[ $1 = "-f" || $1 = "--info" ]]; then # Delete a connection ############## this comment ############ should pass a parameter or show connections.
    ####################### needs work #######################################
    echo "you made it buddy to --info"

else
    mnconnect --help
fi
