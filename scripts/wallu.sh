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
SATOSHI_COINS_UNLOCK="$BTC -rpcwallet=satoshi_coins walletpassphrase $(sudo cat /root/passphrase) 600"
MINING_UNLOCK="$BTC -rpcwallet=mining walletpassphrase $(sudo cat /root/passphrase) 600"
UNLOCK="$BTC -rpcwallet=bank walletpassphrase $(sudo cat /root/passphrase) 600"

# See which wallu parameter was passed and execute accordingly
if [[ $1 = "--help" ]]; then # Show all possible paramters
    cat << EOF
    Options:
      --help        Display this help message and exit
      --install     Install (or upgrade) this script (wallu) in /usr/local/sbin (/satoshiware/microbank/scripts/wallu.sh)
      --cron        (Re)Create a weekly cronjob to send a wallet email update at 6:45 AM on Monday: RECIPIENTS_FIRST_NAME  EMAIL
      --email       Email (send out) the wallet update (requires send_messages to be configured): RECIPIENTS_FIRST_NAME  EMAIL

      --balances    Show balances for the Satoshi Coins, Mining, and Bank wallets

      --send        Send funds (coins) from the Bank wallet <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< make it work for all the wallets, BUT BE CAREFUL with SATOSHI COINS WALLET!!!!
                    Parameters: ADDRESS  AMOUNT  (PRIORITY)
                        Note: Same notes under --transfer routine
      --bump        Bumps the fee of all (recent) outgoing transactions that are BIP 125 replaceable and not confirmed <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
      --scoins      Create new address to receive funds into the Satoshi Coins wallet
      --mining      Create new address to receive funds into the Mining wallet
      --bank        Create new address to receive funds into the Bank wallet
      --recent      Show recent (last 50) Bank wallet transactions <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
EOF
elif [[ $1 == "--install" ]]; then # Install (or upgrade) this script (wallu) in /usr/local/sbin (Repository: /satoshiware/microbank/scripts/pre_fork_micro/wallu.sh)
    echo "Installing this script (wallu) in /usr/local/sbin/"
    if [ -f /usr/local/sbin/wallu ]; then
        echo "This script (wallu) already exists in /usr/local/sbin!"
        read -p "Would you like to upgrade it? (y|n): "
        if [[ "${REPLY}" = "y" || "${REPLY}" = "Y" ]]; then
            sudo rm /usr/local/sbin/wallu
            cd ~; git clone https://github.com/satoshiware/microbank
            bash ~/microbank/scripts/wallu.sh --install
            rm -rf microbank
            exit 0
        else
            exit 0
        fi
    fi

    sudo cat $0 | sudo tee /usr/local/sbin/wallu > /dev/null
    sudo chmod +x /usr/local/sbin/wallu

elif [[ $1 = "--cron" ]]; then # (Re)Create a weekly cronjob to send a wallet email update at 6:45 AM on Monday: RECIPIENTS_NAME  EMAIL
    NAME=$2; EMAIL=$3
    if [[ -z $NAME || -z $EMAIL ]]; then
        echo "Error! Insufficient Parameters!"
        exit 1
    fi

    # Add Weekly Cron Job to send out an email. Run "crontab -e" as $USER to see all its cron jobs.
    (crontab -l | grep -v -F "/usr/local/sbin/wallu --email" ; echo "45 6 * * 1 /bin/bash -lc \"/usr/local/sbin/wallu --email $NAME $EMAIL\"" ) | crontab -

elif [[ $1 = "--email" ]]; then # Email (send out) the wallet update (requires send_messages to be configured): RECIPIENTS_NAME  EMAIL
    NAME=$2; EMAIL=$3
    if [[ -z $NAME || -z $EMAIL ]]; then
        echo "Error! Insufficient Parameters!"
        exit 1
    fi

    MESSAGE="<b>---- Blances ----</b>$(wallu --balances)"
    MESSAGE=${MESSAGE//$'\n'/'<br>'}
    MESSAGE=${MESSAGE// /\&nbsp;}

    send_messages --email $NAME $EMAIL "Bitcoin Wallet Node Snapshot" $MESSAGE

elif [[ $1 = "--balances" ]]; then # Show balances for the Satoshi Coins, Mining, and Bank wallets
    echo ""
    cat << EOF
    Satoshi Coins Wallet:
        Unconfirmed Balance:    $($BTC -rpcwallet=satoshi_coins getbalances | jq '.mine.untrusted_pending' | awk '{printf("%.8f", $1)}')
        Trusted Balance:        $($BTC -rpcwallet=satoshi_coins getbalance)

    Mining Wallet:
        Unconfirmed Balance:    $($BTC -rpcwallet=mining getbalances | jq '.mine.untrusted_pending' | awk '{printf("%.8f", $1)}')
        Trusted Balance:        $($BTC -rpcwallet=mining getbalance)
        Immature Balance:       $($BTC -rpcwallet=mining getbalances | jq '.mine.immature' | awk '{printf("%.8f", $1)}')

    Bank Wallet:
        Unconfirmed Balance:    $($BTC -rpcwallet=bank getbalances | jq '.mine.untrusted_pending' | awk '{printf("%.8f", $1)}')
        Trusted Balance:        $($BTC -rpcwallet=bank getbalance)
EOF
    echo ""

elif [[ $1 = "--send" ]]; then # Send funds (coins) from the Bank wallet
    ADDRESS="${2,,}"; AMOUNT=$3; PRIORITY=${4,,}; TRANSFER=$5

    # Is it an internal transfer
    if [[ $TRANSFER == "INTERNAL" ]]; then
        wallet="mining"
    elif [[ $TRANSFER == "SWEEP" ]]; then
        wallet="import"
    else
        wallet="bank"
    fi

    # Input Checking
    if [[ -z $ADDRESS || -z $AMOUNT ]]; then
        echo "Error! Insufficient Parameters!"; exit 1
    elif ! [[ $($BTC validateaddress $ADDRESS | jq '.isvalid') == "true" ]]; then
        echo "Error! Address provided is not correct or Bitcoin Core (microcurrency mode) is down!"; exit 1
    elif [[ $AMOUNT == "." ]]; then # Should we send it all?
        AMOUNT=$($BTC -rpcwallet=$wallet getbalance) # Get the full amount
        if [[ ! $PRIORITY == "now" ]]; then PRIORITY="normal"; fi # Override priority if set too low
        SEND_ALL=", \"subtract_fee_from_outputs\": [0]" # Extra option for send command in order to empty the Bank wallet completly
    elif ! [[ $AMOUNT =~ ^[0-9]+\.?[0-9]*$ ]]; then
        echo "Error! Amount is not a number!"; exit 1
    elif [[ $(awk '{printf("%15.f\n", $1 * 100000000)}' <<< ${data%?} <<< $AMOUNT) -lt "10000" ]]; then
        echo "Error! Amount is not large enough!"; exit 1
    else
        SEND_ALL=""
    fi

    # Determine paramters that govern fee rate
    if [[ $PRIORITY == "now" ]]; then
        TARGET=1; ESTIMATION="conservative"
    elif [[ -z $PRIORITY || $PRIORITY == "normal" ]]; then
        TARGET=12; ESTIMATION="economical"
    elif [[ $PRIORITY == "economical" ]]; then
        TARGET=144; ESTIMATION="economical"
    elif [[ $PRIORITY == "cheapskate" ]]; then
        TARGET=1008; ESTIMATION="economical"
    else
        echo "Error! Priority could not be determined!"; exit 1
    fi

    $UNLOCK; $MINING_UNLOCK; $BTC -rpcwallet=$wallet send "{\"$ADDRESS\": $AMOUNT}" $TARGET $ESTIMATION null "{\"replaceable\": true${SEND_ALL}}"

elif [[ $1 = "--bump" ]]; then # Bumps the fee of all (recent) outgoing transactions that are BIP 125 replaceable and not confirmed
    WALLETS=("bank" "mining" "import"); bump_flag=""
    for wallet in "${WALLETS[@]}"; do
        readarray -t TXS < <($BTC -rpcwallet=$wallet listtransactions "*" 40 0 false | jq -r '.[] | .confirmations, .txid, .category')
        for ((i = 0 ; i < ${#TXS[@]} ; i = i + 3)); do
            if [[ ${TXS[i]} -eq 0 && ${TXS[i + 2]} == "send" ]]; then
                $UNLOCK; $MINING_UNLOCK; $BTC -rpcwallet=$wallet bumpfee ${TXS[i + 1]}
                bump_flag="true"
            fi
        done
    done

    if [[ -z $bump_flag ]]; then echo "Looks like there is nothing to bump!"; fi

elif [[ $1 = "--scoins" ]]; then # Create new address to receive funds into the Satoshi Coins wallet
    echo ""; $BTC -rpcwallet=satoshi_coins getnewaddress; echo ""

elif [[ $1 = "--mining" ]]; then # Create new address to receive funds into the Mining wallet
    echo ""; $BTC -rpcwallet=mining getnewaddress; echo ""

elif [[ $1 = "--bank" ]]; then # Create new address to receive funds into the Bank wallet
    echo ""; $BTC -rpcwallet=bank getnewaddress; echo ""

elif [[ $1 = "--recent" ]]; then # Show recent (last 40) Bank wallet transactions
    readarray -t TXS < <($BTC -rpcwallet=bank listtransactions "*" 40 0 false | jq -r '.[] | .category, .amount, .confirmations, .time, .address, .txid')

    # Get data from the blockchain
    data=""
    for ((i = 0 ; i < ${#TXS[@]} ; i = i + 6)); do # Go through each address to find the remaining balance and number of UTXOs while prepping the data table
        # How confirmed is the transaction? "Yes" (6 blocks or greater), "Almost" (between 1 and 5 blocks), and "no" (not on the blockchain).
        if [[ ${TXS[i+2]} -ge 6 ]]; then
            TXS[i+2]="Yes"
        elif [[ ${TXS[i+2]} -ge 1 ]]; then
            TXS[i+2]="Almost"
        elif [[ ${TXS[i+2]} -lt 0 ]]; then
            TXS[i+2]="Bumped"
        else
            TXS[i+2]="No"
        fi

        data="$data""${TXS[i]};${TXS[i+1]//-};${TXS[i+2]};$(date -d @${TXS[i+3]} '+%y/%m/%d %H:%M');${TXS[i+4]};${TXS[i+5]}"$'\n' # Direction, Amount, Confirmations, Time, Address, TXID
    done

    # Print data table formatted properly
    echo $'\n'
    echo "Direction       Amount      Confirmed   YY/MM/DD Time   Address                                     TXID"
    echo "---------  ---------------  ---------  ---------------  ------------------------------------------  ----------------------------------------------------------------"
    awk -F ';' '{printf("%7s    %-15.8f  %-8s  %15s   %s  %s\n", $1, $2, $3, $4, $5, $6)}' <<< ${data%?}

else
    $0 --help
    echo "Script Version 0.1"
fi