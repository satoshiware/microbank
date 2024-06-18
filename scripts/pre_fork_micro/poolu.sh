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

# See which poolu parameter was passed and execute accordingly
if [[ $1 = "-h" || $1 = "--help" ]]; then # Show all possible paramters
    cat << EOF
    Options:
      -h, --help    Display this help message and exit
      --install     Install this script (poolu) in /usr/local/sbin/ (Repository: /satoshiware/microbank/scripts/pre_fork_micro/poolu.sh)
      --cron-weekly (Re)Create a weekly cronjob to send mining status email at 6:30 AM on Monday: RECIPIENTS_NAME  EMAIL
      --cron-error  (Re)Create an daily cronjob to notify (via email) of any problems: RECIPIENTS_NAME  EMAIL
      --email       Email (send out) the mining status (requires send_messages to be configured): RECIPIENTS_NAME  EMAIL
      --error       Check for errors and report to user via email (requires send_messages to be configured): RECIPIENTS_NAME  EMAIL
      --remote      Configure inbound connection for a remote mining operation
      --update      Delete log folders (/var/log/ckpool/00*) and if previous mining address has received coins then
                        load a new mining address (/etc/ckpool.conf), delete inactive users (7 days), and restart ckpool
      -s, --status  View the current status of the pool (sudo systemctl status ckpool)
      -m, --miners  Show pool status (/var/log/ckpool/pool/pool.status) and local miners with their respective hashrates (/var/log/ckpool/users)
      -b, --blocks  List the latest (40) blocks solved
      -t, --tail    Display the tail end (40 lines) of the debug log (/var/log/ckpool/ckpool.log)
      -v, --view    View remote connection(s) - Read authorized_keys @ /home/stratum/.ssh/
      -d, --delete  Delete an incoming remote connection: CONNECTION_ID
      -f, --info    Get the connection parameters to setup a remote mining operation
EOF

elif [[ $1 = "--install" ]]; then # Install this script (poolu) in /usr/local/sbin/ (Repository: /satoshiware/microbank/scripts/pre_fork_micro/poolu.sh)
    echo "Installing this script (poolu) in /usr/local/sbin/"
    if [ -f /usr/local/sbin/poolu ]; then
        echo "This script (poolu) already exists in /usr/local/sbin!"
        read -p "Would you like to upgrade it? (y|n): "
        if [[ "${REPLY}" = "y" || "${REPLY}" = "Y" ]]; then
            sudo rm /usr/local/sbin/poolu
            cd ~; git clone https://github.com/satoshiware/microbank
            bash ~/microbank/scripts/pre_fork_micro/poolu.sh --install
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

    sudo cat $0 | sudo tee /usr/local/sbin/poolu > /dev/null
    sudo chmod +x /usr/local/sbin/poolu

    # Add hourly Cron Job to run the update routine. Run "crontab -l" as $USER to see all its cron jobs.
    (crontab -l | grep -v -F "/usr/local/sbin/poolu --update" ; echo "0 * * * * /usr/local/sbin/poolu --update" ) | crontab -

elif [[ $1 = "--cron-weekly" ]]; then # (Re)Create a weekly cronjob to send mining status email at 6:30 AM on Monday: RECIPIENTS_NAME  EMAIL
    NAME=$2; EMAIL=$3
    if [[ -z $NAME || -z $EMAIL ]]; then
        echo "Error! Insufficient Parameters!"
        exit 1
    fi

    # Add Weekly Cron Job to send out an email update. Run "crontab -l" as $USER to see all its cron jobs.
    (crontab -l | grep -v -F "/usr/local/sbin/poolu --email" ; echo "30 6 * * 1 /usr/local/sbin/poolu --email $NAME $EMAIL" ) | crontab -

elif [[ $1 = "--cron-error" ]]; then # (Re)Create an daily cronjob to notify (via email) of any problems: RECIPIENTS_NAME  EMAIL
    NAME=$2; EMAIL=$3
    if [[ -z $NAME || -z $EMAIL ]]; then
        echo "Error! Insufficient Parameters!"
        exit 1
    fi

    # Add hourly Cron Job to check for errors. Run "crontab -l" as $USER to see all its cron jobs.
    (crontab -l | grep -v -F "/usr/local/sbin/poolu --error" ; echo "0 0 * * * /usr/local/sbin/poolu --error $NAME $EMAIL" ) | crontab -

elif [[ $1 = "--email" ]]; then # Email (send out) the mining status (requires send_messages to be configured): RECIPIENTS_NAME  EMAIL
    NAME=$2; EMAIL=$3
    if [[ -z $NAME || -z $EMAIL ]]; then
        echo "Error! Insufficient Parameters!"
        exit 1
    fi

    MESSAGE="<b>---- Miners ----</b>$(poolu --miners)<br><br><b>---- Last 40 Blocks ----</b>$(poolu --blocks)<br><br><b>---- Debug Log ----</b>$(poolu --tail)"
    MESSAGE=${MESSAGE//$'\n'/'<br>'}
    MESSAGE=${MESSAGE// /\&nbsp;}

    send_messages --email $NAME $EMAIL "Mining Pool Snapshot" $MESSAGE

elif [[ $1 = "--error" ]]; then # Check for errors and report to user via email (requires send_messages to be configured): RECIPIENTS_NAME  EMAIL
    NAME=$2; EMAIL=$3
    if [[ -z $NAME || -z $EMAIL ]]; then
        echo "Error! Insufficient Parameters!"
        exit 1
    fi

    # Make sure the pool software is running
    if [[ ! $(systemctl is-active ckpool) == "active" ]]; then
        send_messages --email $NAME $EMAIL "Pool Software Has Stopped" "Hey you, your mining pool software is not running."
        exit 0
    fi

    # Make sure the pool is hashing (has it been down for more than 6 hours?)
    if [[ $(sudo sed '2!d' /var/log/ckpool/pool/pool.status | jq -r '.hashrate6hr') == "0" ]]; then
        send_messages --email $NAME $EMAIL "Pool Is Not Hashing" "Hey you, your mining pool is not hashing.<br>Potentially, the miner(s) are down or the Stratum Node has become disconnected from the P2P Node."
        exit 0
    fi

    # Has there been a miner down for more than an hour?
    sudo find /var/log/ckpool/users -name '* *' -exec sh -c '
        for file do
            dir=${file%/*};
            file=${file##*/};
            without_spaces=$(printf %s "$file." | sed "s/ /_/g")
            sudo mv "$dir/$file" "$dir/${without_spaces%.}";
        done
    ' _ {} + # Convert spaces " " in each filename to underscores '_' (prevents processing errors in the next step)

    users=($(sudo ls /var/log/ckpool/users))
    for u in "${users[@]}"; do
        if [[ $(sudo cat /var/log/ckpool/users/$u | jq -r '.hashrate1hr') == "0" ]]; then
            send_messages --email $NAME $EMAIL "Miner $u Stopped Working" "Hey you, it has been a while since your miner \"$u\" has submitted any shares."
        fi
    done

elif [[ $1 = "--remote" ]]; then # Configure inbound connection for a remote mining operation
    echo "Configuring inbound connection for a remote mining operation..."
    read -p "Remote Connection Name: " CONNNAME
    read -p "Remote Operation's (Public) Key: " PUBLICKEY
    TMSTAMP=$(date +%s)

    echo "${PUBLICKEY} # ${CONNNAME}, CONN_ID: ${TMSTAMP}, REMOTE" | sudo tee -a /home/stratum/.ssh/authorized_keys

elif [[ $1 = "--update" ]]; then # Delete log folders (/var/log/ckpool/00*) and if previous mining address has received coins then load a new mining address (/etc/ckpool.conf), delete inactive users (7 days), and restart ckpool
    # Delete all log folder that start with "00" except for the latest one in the directory /var/log/ckpool
    sudo find /var/log/ckpool -regex '^.*\/00.*' ! -name "$(sudo find /var/log/ckpool -regex '^.*\/00.*' -type d | sort | tail -n 1 | cut -d '/' -f 5)" -type d -exec rm -rf {} +

    ADDRESS=$(sudo sed -n '/btcaddress/p' /etc/ckpool.conf | cut -d "\"" -f 4) # Get current mining address
    if [[ $($BTC -rpcwallet=mining listtransactions "*" 5000 0 false | grep "$ADDRESS" | wc -l) -gt 0 ]]; then # Check mining address to see if it is in the blockchain.
        sudo systemctl stop ckpool # Stop the pool
        sleep 10 # Wait 10 seconds while ckpool service is stopping

        sudo sed -i "/btcaddress/c\"btcaddress\" : \"$($BTC -rpcwallet=mining getnewaddress)\"," /etc/ckpool.conf # Load a new mining address

        # Delete inactive miners (havn't mined for over a week)
        sudo find /var/log/ckpool/users -name '* *' -exec sh -c '
            for file do
                dir=${file%/*};
                file=${file##*/};
                without_spaces=$(printf %s "$file." | sed "s/ /_/g")
                sudo mv "$dir/$file" "$dir/${without_spaces%.}";
            done
        ' _ {} +  # Convert spaces " " in each filename to underscores '_' (prevents processing errors in the next step)

        users=($(sudo ls /var/log/ckpool/users))
        echo ""
        for u in "${users[@]}"; do
            if [[ $(sudo cat /var/log/ckpool/users/$u | jq -r '.hashrate7d') == "0" ]]; then
                sudo rm /var/log/ckpool/users/$u
            fi
        done

        sudo systemctl start ckpool # Start the pool
    fi

elif [[ $1 = "-s" || $1 = "--status" ]]; then # View the current status of the pool (sudo systemctl status ckpool)
    sudo systemctl status ckpool

elif [[ $1 = "-m" || $1 = "--miners" ]]; then # Show pool status (/var/log/ckpool/pool/pool.status) and local miners with their respective hashrates (/var/log/ckpool/users)
    echo -n "Workers: "; sudo head -n 1 /var/log/ckpool/pool/pool.status | jq -r '.Users'
    echo -n "   Idle: "; sudo head -n 1 /var/log/ckpool/pool/pool.status | jq -r '.Idle'
    echo -n "   Disconnected: "; sudo head -n 1 /var/log/ckpool/pool/pool.status | jq -r '.Disconnected'
    echo ""

    echo "Pool Hashrate:"
    echo -n "   1m: "; sudo sed '2!d' /var/log/ckpool/pool/pool.status | jq -r '.hashrate1m'
    echo -n "   5m: "; sudo sed '2!d' /var/log/ckpool/pool/pool.status | jq -r '.hashrate5m'
    echo -n "   15m: "; sudo sed '2!d' /var/log/ckpool/pool/pool.status | jq -r '.hashrate15m'
    echo -n "   1hr: "; sudo sed '2!d' /var/log/ckpool/pool/pool.status | jq -r '.hashrate1hr'
    echo -n "   6hr: "; sudo sed '2!d' /var/log/ckpool/pool/pool.status | jq -r '.hashrate6hr'
    echo -n "   1d: "; sudo sed '2!d' /var/log/ckpool/pool/pool.status | jq -r '.hashrate1d'
    echo -n "   7d: "; sudo sed '2!d' /var/log/ckpool/pool/pool.status | jq -r '.hashrate7d'
    echo ""

    # Convert spaces " " in each filename to underscores '_' (prevents processing errors in the next step)
    sudo find /var/log/ckpool/users -name '* *' -exec sh -c '
        for file do
            dir=${file%/*};
            file=${file##*/};
            without_spaces=$(printf %s "$file." | sed "s/ /_/g")
            sudo mv "$dir/$file" "$dir/${without_spaces%.}";
        done
    ' _ {} +

    # Print hashrates for each worker (user file)
    users=($(sudo ls /var/log/ckpool/users))
    echo ""
    for u in "${users[@]}"; do
        echo "Worker Hashrate: $u"
        echo -n "   1m: "; sudo cat /var/log/ckpool/users/$u | jq -r '.hashrate1m'
        echo -n "   5m: "; sudo cat /var/log/ckpool/users/$u | jq -r '.hashrate5m'
        echo -n "   1hr: "; sudo cat /var/log/ckpool/users/$u | jq -r '.hashrate1hr'
        echo -n "   1d: "; sudo cat /var/log/ckpool/users/$u | jq -r '.hashrate1d'
        echo -n "   7d: "; sudo cat /var/log/ckpool/users/$u | jq -r '.hashrate7d'
        echo ""
    done

elif [[ $1 = "-b" || $1 = "--blocks" ]]; then # List the latest (40) blocks solved
    # Get range of block heights
    BLOCKHEIGHT=$($BTC getblockcount)
    regex='^[0-9]+$'
    if ! [[ $BLOCKHEIGHT =~ $regex ]]; then
        echo "Error! bitcoind is not responding!"
        exit 1
    fi
    START=$((BLOCKHEIGHT-39))

    # Loop through each block and report
    for (( i=$START; i<=$BLOCKHEIGHT; i++ ));do
        block_hash=$($BTC getblockhash $i)
        block=$($BTC getblock $block_hash)
        coinbase_hash=$(echo $block | jq -r '.tx[0]')
        coinbase=$($BTC getrawtransaction $coinbase_hash 1)
        source_hex=$(echo $(echo $coinbase | jq -r '.vin[0].coinbase' | sed 's/^.*636b706f6f6c..\?//')) # Remove everything up to the ascii text "ckpool" (0x636b706f6f6c) + one byte. Everything left is the owner's name (in ascii)
        source_hex_delimented=$(echo $source_hex | sed 's/\([0-9AF]\{2\}\)/\\\x\1/gI') # Start each byte with '\x' so the printf command can properly interpret
        source_txt=$(printf $source_hex_delimented)

        echo -n -e "Height: $i        Size (bytes): $(echo $block | jq '.size')"
        echo -n -e "        Value (coins): $(echo $coinbase | jq '.vout[0].value')"
        echo -e "        Source: $source_txt"
    done

elif [[ $1 = "-t" || $1 = "--tail" ]]; then # Display the tail end (40 lines) of the debug log (/var/log/ckpool/ckpool.log)
    sudo tail /var/log/ckpool/ckpool.log -n 40

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
    echo "Script Version 0.10"
fi