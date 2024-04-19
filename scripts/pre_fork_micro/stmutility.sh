#!/bin/bash

### TODOS: The whole script needs a lot of work. The help is complete, but it could possibly use a description block.
### Need to make the update routine so it can run with as root. This script stops if is run as root.
### Did the log rotate work for the stratum log files?????????????????? micronode level 3


#Update/Upgrade "stratum" micronode utilities
#    cd ~; git clone https://github.com/satoshiware/microbank
#    bash ~/microbank/scripts/pre_fork_micro/stmutility.sh -i
#    rm -rf microbank

# Make sure we are not running as root, but that we have sudo privileges.
if [ "$(id -u)" = "0" ]; then
   echo "This script must NOT be run as root (or with sudo)!"
   exit 1
elif [ "$(sudo -l | grep '(ALL : ALL) ALL' | wc -l)" = 0 ]; then
   echo "You do not have enough sudo privileges!"
   exit 1
fi

# Install this script (stmutility) in /usr/local/sbin
if [[ $1 = "-i" || $1 = "--install" ]]; then
    echo "Installing this script (stmutility) in /usr/local/sbin/"
    if [ ! -f /usr/local/sbin/stmutility ]; then
        sudo cat $0 | sed '/Install this script/d' | sudo tee /usr/local/sbin/stmutility > /dev/null
        sudo sed -i 's/$1 = "-i" || $1 = "--install"/"a" = "b"/' /usr/local/sbin/stmutility # Make it so this code won't run again in the newly installed script.
        sudo chmod +x /usr/local/sbin/stmutility
    else
        echo "\"stmutility\" already exists in /usr/local/sbin!"
        read -p "Would you like to uninstall it? (y|n): "
        if [[ "${REPLY}" = "y" || "${REPLY}" = "Y" ]]; then
            sudo rm /usr/local/sbin/stmutility
        fi
    fi
    exit 0
fi

# Make sure this script is installed
if [ ! -f /usr/local/sbin/stmutility ]; then
    echo "Error: this script is not yet installed to \"/usr/local/sbin/stmutility\"!"
    echo "Rerun this script with the \"-i\" or \"--install\" parameter!"
    exit 1
fi

# See which stmutility parameter was passed and execute accordingly
if [[ $1 = "-h" || $1 = "--help" ]]; then # Show all possible paramters
    cat << EOF
    Options:
      -i, --install     Install this script (stmutility) in /usr/local/sbin/
      -h, --help        Display this help message and exit
      -r, --remote      Configure inbound connection for a remote mining operation
      -u, --update      Load a new mining address if the previous one has been used
      -s, --status      View the current status of the pool
      -m, --miners      Show miners and hashrates
      -b, --blocks      List the latest (40) blocks solved
      -t, --tail        Display the tail end of the debug log

    With this tool, you can view all the pertinent information to ensure a healthy mining operation.
    Also, with this tool and the help of the mnconnect utility, you can set up an incoming connection for a remote mining operation.
        Run the "~/microbank/micronode_stratum_remote.sh" on a SBC (e.g. Raspberry Pi Zero 2) to set it up for the "Remote Access Point"

Pertinent file locations:
    /usr/local/sbin/stmutility
    /var/log/ckpool/ckpool.log
    /var/log/ckpool/users/*     # There's a file for each miner
    /var/log/ckpool/pool/pool.status
    /home/p2p/.ssh/authorized_keys

Notes:
    Once configured, just point the miner(s) to this node (or the "Remote Access Point") via its private network static ip on port 3333.
        Example: stratum+tcp://$IP_ADDRESS:3333
    Run the "usb_miner.sh" on a SBC (e.g. Raspberry Pi Zero 2W [WIRELESS]) to setup and run a USB miner (e.g. R909)
EOF

elif [[ $1 = "-r" || $1 = "--remote" ]]; then # Configure inbound connection for a remote mining operation
    echo "Configuring inbound connection for a remote mining operation..."
    read -p "Brief Remote Connection Description: " CONNNAME
    read -p "Remote Operation's P2P (Public) Key: " P2PKEY
    TMSTAMP=$(date +%s)

    echo "${P2PKEY} # ${CONNNAME}, ${TMSTAMP}, REMOTE" | sudo tee -a /home/p2p/.ssh/authorized_keys

elif [[ $1 = "-u" || $1 = "--update" ]]; then # Load a new mining address if the previous one has been used
    echo "We have work here to do!"
    #Delete inactive miners (havn't mined for over a week or something)
    #restart the pool.
    #Delete all those extra folders that are a 100 blcks old???

elif [[ $1 = "-s" || $1 = "--status" ]]; then # View the current status of the pool
    cat /var/log/ckpool/pool/pool.status

    ## Is Bitcoind running?
    ## Is the node connected?
    ## Is ckpool running?
    ## When was the last block solved??

elif [[ $1 = "-m" || $1 = "--miners" ]]; then # Show miners and hashrates
    ls /var/log/ckpool/users
    #Make a seperate section for inactive miners (these miners will be deleted on next --update call)

elif [[ $1 = "-b" || $1 = "--blocks" ]]; then # List the latest (40) blocks solved
    echo "ok"

elif [[ $1 = "-t" || $1 = "--tail" ]]; then # Display the tail end of the debug log
    echo "ok"

else
    $0 --help
fi