#!/bin/bash

# Make sure we are not running as root, but that we have sudo privileges.
if [ "$(id -u)" = "0" ]; then
   echo "This script must NOT be run as root (or with sudo)!"
   exit 1
elif [ "$(sudo -l | grep '(ALL : ALL) ALL' | wc -l)" = 0 ]; then
   echo "You do not have enough sudo privileges!"
   exit 1
fi

# See which stmutility parameter was passed and execute accordingly
if [[ $1 = "-h" || $1 = "--help" ]]; then # Show all possible paramters
    cat << EOF
    Options:
      -h, --help        Display this help message and exit
      -i, --install     Install this script (stmutility) in /usr/local/sbin/ (Repository: /satoshiware/microbank/scripts/pre_fork_micro/stmutility.sh)
      -r, --remote      Configure inbound connection for a remote mining operation
!!!!! -u, --update      Load a new mining address (if previous one is used), cleanup log folders (/var/log/ckpool/*), delete inactive user (/var/log/ckpool/users/*), restart the pool
      -s, --status      View the current status of the pool??????????????/var/log/ckpool/pool/pool.status
      -m, --miners      Show miners and hashrates ?????????????????????????????????????
      -b, --blocks      List the latest (40) blocks solved ?????????????????????????????
      -t, --tail        Display the tail end of the debug log (/var/log/ckpool/ckpool.log) ????????????????????
	  -v, --view        View remote connection(s) - Read authorized_keys @ /home/stratum/.ssh/
      -d, --delete      Delete an incoming remote connection: CONNECTION_ID
      -f, --info        Get the connection parameters to setup a remote mining operation
	  

    With this tool, you can view all the pertinent information to ensure a healthy mining operation.
    Also, with this tool and the help of the mnconnect utility, you can set up an incoming connection for a remote mining operation.
        Run the "~/microbank/micronode_stratum_remote.sh" on a SBC (e.g. Raspberry Pi Zero 2) to set it up for the "Remote Access Point"

 $(ls -d 00* | tail -n 1) # Remove all log folders except the last one

rm rf 00* !("$(ls -d 00* | tail -n 1)"|"filename2") -v

rm rf 00* !("$(ls -d 00* | tail -n 1)"|"filename2") -v

rm -v !("filename1")


find ./00* ! -name 'file.txt' -type f -exec rm -rf {} +



find ./00* ! -name "$(ls -d 00* | tail -n 1)" -type d -exec rm -rf {} +
    
    

Notes:
    Once configured, just point the miner(s) to this node (or the "Remote Access Point") via its private network static ip on port 3333.
        Example: stratum+tcp://$IP_ADDRESS:3333
    Run the "usb_miner.sh" on a SBC (e.g. Raspberry Pi Zero 2W [WIRELESS]) to setup and run a USB miner (e.g. R909)
EOF
elif [[ $1 = "--install" ]]; then # Install this script (stmutility) in /usr/local/sbin/ (Repository: /satoshiware/microbank/scripts/pre_fork_micro/stmutility.sh)
    echo "Installing this script (stmutility) in /usr/local/sbin/"
    if [ -f /usr/local/sbin/stmutility ]; then
        echo "This script (stmutility) already exists in /usr/local/sbin!"
        read -p "Would you like to upgrade it? (y|n): "
        if [[ "${REPLY}" = "y" || "${REPLY}" = "Y" ]]; then
            sudo rm /usr/local/sbin/stmutility
            cd ~; git clone https://github.com/satoshiware/microbank
            bash ~/microbank/scripts/stmutility.sh --install
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
	
    sudo cat $0 | sudo tee /usr/local/sbin/stmutility > /dev/null
    sudo chmod +x /usr/local/sbin/stmutility
	
elif [[ $1 = "-r" || $1 = "--remote" ]]; then # Configure inbound connection for a remote mining operation
    echo "Configuring inbound connection for a remote mining operation..."
    read -p "Remote Connection Name: " CONNNAME
    read -p "Remote Operation's (Public) Key: " PUBLICKEY
    TMSTAMP=$(date +%s)

    echo "${PUBLICKEY} # ${CONNNAME}, CONN_ID: ${TMSTAMP}, REMOTE" | sudo tee -a /home/stratum/.ssh/authorized_keys

elif [[ $1 = "-u" || $1 = "--update" ]]; then # Load a new mining address (if previous one is used), cleanup log folders, delete inactive user, restart the pool

	########### Is there a way to suspend this service?????
	# Delete all log folder that start with "00" except for the latest one in the directory /var/log/ckpool
	sudo find /var/log/ckpool -regex '^.*\/00.*' ! -name "$(sudo find /var/log/ckpool -regex '^.*\/00.*' -type d | sort | tail -n 1 | cut -d '/' -f 5)" -type d -exec rm -rf {} +
		
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





    sudo sed -i "/${2}/d" /root/.ssh/known_hosts 2> /dev/null # Remove the known host containing the time stamp
	
	
	

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

    echo "Local IP: $(hostname -I)" | sudo tee -a /etc/micronode.info

    if [ -z ${SSHPORT+x} ]; then SSHPORT="22"; fi
    echo "SSH Port: ${SSHPORT}" | sudo tee -a /etc/micronode.info

    # Remove unwanted/unused host keys
    sudo rm /etc/ssh/ssh_host_dsa_key* 2> /dev/null
    sudo rm /etc/ssh/ssh_host_ecdsa_key* 2> /dev/null
    sudo rm /etc/ssh/ssh_host_rsa_key* 2> /dev/null

    echo "Host Key (Public): $(sudo cat /etc/ssh/ssh_host_ed25519_key.pub | sed 's/ root@.*//')" | sudo tee -a /etc/micronode.info
    echo "P2P Key (Public): $(sudo cat /root/.ssh/p2pkey.pub)" | sudo tee -a /etc/micronode.info

    sudo chmod 400 /etc/micronode.info



elif [[ $1 = "-v" || $1 = "--view" ]]; then # View remote connection(s) - Read authorized_keys @ /home/stratum/.ssh/
	sudo cat /home/stratum/.ssh/authorized_keys

elif [[ $1 = "-d" || $1 = "--delete" ]]; then # Delete an incoming remote connection: CONNECTION_ID
    if [[ ! ${#} = "2" ]]; then
        echo "Enter the Connection ID to delete (Example: \"mnconnect --delete 1691422785\")."
        exit 0
    fi

    # Delete inbound connections
    sudo sed -i "/${2}/d" /home/stratum/.ssh/authorized_keys 2> /dev/null # Remove the key with a comment containing the passed "time stamp"

    # Force disconnect all users
    STRATUM_PIDS=$(ps -u stratum 2> /dev/null | grep sshd)
    while IFS= read -r line ; do sudo kill -9 $(echo $line | cut -d ' ' -f 1) 2> /dev/null; done <<< "$STRATUM_PIDS"
	
elif [[ $1 = "-f" || $1 = "--info" ]]; then # Get the connection parameters to setup a remote mining operation
    mnconnect --key
    echo "Host Key (Public): $(sudo cat /etc/ssh/ssh_host_ed25519_key.pub | sed 's/ root@.*//')"

else
    $0 --help
	echo "Script Version 0.01"
fi