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

      --send        Send funds (coins) from the (bank | mining | satoshi_coins) wallet
                    Parameters: ADDRESS  AMOUNT  WALLET  (PRIORITY)
                        Note: PRIORITY is optional (default = NORMAL). It helps determine the fee rate.
                              It can be set to NOW, NORMAL (6 hours), ECONOMICAL (1 day), or CHEAPSKATE (1 week).
                        Note: Enter '.' for the amount to empty the wallet completly (NORMAL priority is enforced)
                        Note: DON'T USE with the satoshi_coins wallet; it may invalidate your Satoshi Coins' chain!!!

      --bump        Bumps the fee of all (recent) outgoing transactions that are BIP 125 replaceable and not confirmed (bank and mining wallets only)
      --mining      Create new address to receive funds into the Mining wallet
      --bank        Create new address to receive funds into the Bank wallet
      --recent      Show recent (last 50) Bank wallet transactions

      ####################### Satoshi Coins ###############################
      --scoins      Create new address to receive funds into the Satoshi Coins wallet
      --create      Start new Satoshi Coins' chain: NAME_OF_BANK_OPERATION  (PRIORITY)
      --load        Load Satoshi Coins: TXID_SATOSHI_COIN_CHAIN_TIP  AMOUNT_PER_COIN  (PRIORITY)
      --destory     Bring a Satoshi Coins' chain to an end: TXID_SATOSHI_COIN_CHAIN_TIP
                        Note: PRIORITY is optional (default = NORMAL). It helps determine the fee rate.
                        Options: NOW, NORMAL (6 hours), ECONOMICAL (1 day), or CHEAPSKATE (1 week).
      --log         Show log (/var/log/satoshicoins/log)
EOF
elif [[ $1 == "--install" ]]; then # Install (or upgrade) this script (wallu) in /usr/local/sbin (Repository: /satoshiware/microbank/scripts/wallu.sh)
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
    Bank Wallet:
        Unconfirmed Balance:    $($BTC -rpcwallet=bank getbalances | jq '.mine.untrusted_pending' | awk '{printf("%.8f", $1)}')
        Trusted Balance:        $($BTC -rpcwallet=bank getbalance)

    Mining Wallet:
        Unconfirmed Balance:    $($BTC -rpcwallet=mining getbalances | jq '.mine.untrusted_pending' | awk '{printf("%.8f", $1)}')
        Trusted Balance:        $($BTC -rpcwallet=mining getbalance)
        Immature Balance:       $($BTC -rpcwallet=mining getbalances | jq '.mine.immature' | awk '{printf("%.8f", $1)}')

    Satoshi Coins Wallet:
        Unconfirmed Balance:    $($BTC -rpcwallet=satoshi_coins getbalances | jq '.mine.untrusted_pending' | awk '{printf("%.8f", $1)}')
        Trusted Balance:        $($BTC -rpcwallet=satoshi_coins getbalance)
EOF
    echo ""

elif [[ $1 = "--send" ]]; then # Send funds (coins) from the (bank | mining | satoshi_coins) wallet
    ADDRESS="${2,,}"; AMOUNT=$3; WALLET=${4,,}; PRIORITY=${5,,} # Parameters: ADDRESS  AMOUNT  WALLET  (PRIORITY)

    # Input Checking
    if [[ -z $ADDRESS || -z $AMOUNT || -z $WALLET ]]; then
        echo "Error! Insufficient Parameters!"; exit 1
    elif ! [[ $($BTC validateaddress $ADDRESS | jq '.isvalid') == "true" ]]; then
        echo "Error! Address provided is not correct or Bitcoin Core is down!"; exit 1
    elif [[ $AMOUNT == "." ]]; then # Should we send it all?
        AMOUNT=$($BTC -rpcwallet=$WALLET getbalance) # Get the full amount
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
        TARGET=6; ESTIMATION="conservative"
    elif [[ -z $PRIORITY || $PRIORITY == "normal" ]]; then
        TARGET=36; ESTIMATION="economical"
    elif [[ $PRIORITY == "economical" ]]; then
        TARGET=144; ESTIMATION="economical"
    elif [[ $PRIORITY == "cheapskate" ]]; then
        TARGET=1008; ESTIMATION="economical"
    else
        echo "Error! Priority could not be determined!"; exit 1
    fi

    $UNLOCK; $MINING_UNLOCK; $BTC -rpcwallet=$WALLET send "{\"$ADDRESS\": $AMOUNT}" $TARGET $ESTIMATION null "{\"replaceable\": true${SEND_ALL}}"

elif [[ $1 = "--bump" ]]; then # Bumps the fee of all (recent) outgoing transactions that are BIP 125 replaceable and not confirmed (bank and mining wallets only)
    WALLETS=("bank" "mining"); bump_flag=""
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

elif [[ $1 = "--mining" ]]; then # Create new address to receive funds into the Mining wallet
    echo ""; $BTC -rpcwallet=mining getnewaddress; echo ""

elif [[ $1 = "--bank" ]]; then # Create new address to receive funds into the Bank wallet
    echo ""; $BTC -rpcwallet=bank getnewaddress; echo ""

elif [[ $1 = "--recent" ]]; then # Show recent (last 50) Bank wallet transactions
    readarray -t TXS < <($BTC -rpcwallet=bank listtransactions "*" 50 0 false | jq -r '.[] | .category, .amount, .confirmations, .time, .address, .txid')

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

############################# Satoshi Coins ###############################
elif [[ $1 = "--scoins" ]]; then # Create new address to receive funds into the Satoshi Coins wallet
    echo ""; $BTC -rpcwallet=satoshi_coins getnewaddress; echo ""

elif [[ $1 = "--create" ]]; then # Start new Satoshi Coins' chain
    NAME_OF_BANK_OPERATION="${2^^}"; PRIORITY=${3,,} # Parameters: NAME_OF_BANK_OPERATION  (PRIORITY)

    # Constants
    NAME_OF_BANK_OPERATION="HELLO WORLD" # Uncomment for testing purposes ###################################?????????????
    #HEXSTRING="5341544f53484920434f494e533a20" # ASCII HEX: "SATOSHI COINS: " ##############################?????????????
    HEXSTRING="544553543a20" # ASCII HEX: "TEST: " ##########################################################?????????????
    #WALLET="satoshi_coins" #################################################################################?????????????
    WALLET="testing" ########################################################################################?????????????

    # Make sure satoshi coins' log file and corresponding directory exist
    sudo mkdir -p /var/log/$WALLET
    sudo touch /var/log/$WALLET/log

    # Input Checking
    if [[ -z $NAME_OF_BANK_OPERATION ]]; then
        echo "Error! Insufficient Parameters!"; exit 1
    fi

    # Determine paramters that govern fee rate
    if [[ $PRIORITY == "now" ]]; then
        TARGET=6; ESTIMATION="conservative"
    elif [[ -z $PRIORITY || $PRIORITY == "normal" ]]; then
        TARGET=36; ESTIMATION="economical"
    elif [[ $PRIORITY == "economical" ]]; then
        TARGET=144; ESTIMATION="economical"
    elif [[ $PRIORITY == "cheapskate" ]]; then
        TARGET=1008; ESTIMATION="economical"
    else
        echo "Error! Priority could not be determined!"; exit 1
    fi

    # Verify there is no active chain
    if [[ $(($(grep -c "NEW_CHAIN" "/var/log/$WALLET/log") - $(grep -c "DELETE_CHAIN" "/var/log/$WALLET/log"))) -ne 0 ]]; then
        echo "Error! There is already an active chain!"
        tail /var/log/$WALLET/log -n 1
        exit 1
    fi

    # Prepare and send the transaction; it will also combine all CONFIRMED utxos into one.
    read -p "Creating new Chain: \"$NAME_OF_BANK_OPERATION\". Would you like to continue? (y|n): "
    if [[ "${REPLY}" = "y" || "${REPLY}" = "Y" ]]; then
        HEXSTRING="${HEXSTRING}$(echo -n $NAME_OF_BANK_OPERATION | od -An -tx1 | sed 's/ //g' | sed ':a;N;$!ba;s/\n//g')"
        OUTPUT=$($BTC -rpcwallet=$WALLET -named send estimate_mode=economical conf_target=$TARGET \
        outputs="[{\"$($BTC -rpcwallet=$WALLET getnewaddress)\":$($BTC -rpcwallet=$WALLET getbalance)},{\"data\":\"$HEXSTRING\"}]" \
        options="{\"change_position\":0,\"replaceable\":true,\"subtract_fee_from_outputs\":[0]}")

        # Check for valid TXID; if valid, output to log.
        TXID=$(echo $OUTPUT | jq -r .txid)
        if [[ ${#TXID} -eq 64 && "$TXID" =~ ^[0-9a-fA-F]+$ ]]; then
            echo "NEW_CHAIN: \"$NAME_OF_BANK_OPERATION\" TXID:$TXID DATA:$HEXSTRING TIME:$(date +%s)" | sudo tee -a /var/log/$WALLET/log
        else
            echo $OUTPUT; exit 1
        fi
    fi

elif [[ $1 = "--load" ]]; then # Load Satoshi Coins
    TXID_SATOSHI_COIN_CHAIN_TIP=$2; AMOUNT_PER_COIN=$3; PRIORITY=${4,,} # Parameters: TXID_SATOSHI_COIN_CHAIN_TIP  AMOUNT_PER_COIN  (PRIORITY)

    # Constants
    TXID_SATOSHI_COIN_CHAIN_TIP="bb43455dcb8f1b872cd25de7640299134412dd01944d3133ce50a5e5f2de299e" #############################################??????
    AMOUNT_PER_COIN=10000  #####################################################################################################################??????
    #WALLET="satoshi_coins" ####################################################################################################################??????
    WALLET="testing" ###########################################################################################################################??????

    # Input Checking
    if [[ -z $TXID_SATOSHI_COIN_CHAIN_TIP || -z $AMOUNT_PER_COIN ]]; then
        echo "Error! Insufficient Parameters!"; exit 1
    fi
    if ! [[ ${#TXID_SATOSHI_COIN_CHAIN_TIP} -eq 64 && "$TXID_SATOSHI_COIN_CHAIN_TIP" =~ ^[0-9a-fA-F]+$ ]]; then
        echo "Error! Invalid Chain tip TXID! Please enter a valid 64-character hex string."; exit 1
    fi

    # Verify there is an active chain
    if [[ $(($(grep -c "NEW_CHAIN" "/var/log/$WALLET/log") - $(grep -c "DELETE_CHAIN" "/var/log/$WALLET/log"))) -eq 0 ]]; then
        echo "Error! There is already no active chain!"; exit 1
    fi

    # Verify TXID is a valid chain tip
    if [[ -z $(tac /var/log/$WALLET/log | grep -m 1 -E "NEW_CHAIN|LOAD" | grep $TXID_SATOSHI_COIN_CHAIN_TIP) ]]; then
        echo "Error! The TXID given is not a valid Chain Tip!"; ##exit 1
    fi

    # Verify TXID has an unspent utxo on the first output
    if [[ -z $($BTC -rpcwallet=$WALLET listunspent 0 | grep $TXID_SATOSHI_COIN_CHAIN_TIP -A 1 | grep "vout\": 0") ]]; then
        echo "Error! The Chain Tip TXID has no unspent utxo @ index 0!"; exit 1
    fi

    # Check if the coin amount is valid
    case "$AMOUNT_PER_COIN" in
        1000000|500000|250000|100000|50000|25000|10000)
            echo "\$ATS Per Coin: $AMOUNT_PER_COIN"
            ;;
        *)
            echo "Invalid input: $AMOUNT_PER_COIN"
            echo "Allowed values are 10000, 25000, 50000, 100000, 250000, 500000, or 1000000."
            exit 1
            ;;
    esac

    # Determine paramters that govern fee rate
    if [[ $PRIORITY == "now" ]]; then
        TARGET=6; ESTIMATION="conservative"
    elif [[ -z $PRIORITY || $PRIORITY == "normal" ]]; then
        TARGET=36; ESTIMATION="economical"
    elif [[ $PRIORITY == "economical" ]]; then
        TARGET=144; ESTIMATION="economical"
    elif [[ $PRIORITY == "cheapskate" ]]; then
        TARGET=1008; ESTIMATION="economical"
    else
        echo "Error! Priority could not be determined!"; exit 1
    fi

    # Start scanning the public addresses on each coin
    unset coins # Clear the array
    declare -A coins # Initialize an empty associative array to store unique coin addresses
    while true; do # Loop to receive multiple coins
        read -p "Enter the next coin's public address (or type 'done' to stop): " user_input # Prompt the user for input

        # Allow the user to type 'done' to stop input
        if [ "$user_input" == "done" ]; then
            break
        fi

        # Convert the input to lowercase
        user_input=$(echo "$user_input" | tr 'A-Z' 'a-z')

        # Check if the coin address is valid (bech32)
        if [[ $($BTC validateaddress $user_input | jq .isvalid) != "true" ]]; then
            echo "Error: Invalid address!"; continue
        fi

        # Check if the input is a duplicate
        if [[ -n "${coins[$user_input]}" ]]; then
            echo "Error: This address has already been entered."; continue
        fi

        coins["$user_input"]=1 # Store the valid input in the associative array (key is the input string)
    done

    # Show all valid unique inputs
    echo ""; echo ""; echo "All valid unique coin addresses: "
    for address in "${!coins[@]}"; do
        echo "    $address"
    done; echo ""

    # Get wallet balance (in $ATS)
    BALANCE=$(awk -v balance="$($BTC -rpcwallet=$WALLET getbalance)" 'BEGIN {printf("%.0f", balance * 100000000)}' </dev/null)

    # Get Fee Rate (BTC / kB) from full node !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!   satoshi:satoshi@192.168.2.12:8332 !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    FEE_RATE=$(curl -s --data-binary "{\"jsonrpc\":\"2.0\",\"id\":\"SCEstimateSmartFee\",\"method\":\"estimatesmartfee\",\"params\":[$TARGET]}" -H 'content-type:text/plain;' satoshi:satoshi@192.168.2.12:8332 | jq '.result.feerate')
    FEE_RATE=$(awk -v decimal="$FEE_RATE" 'BEGIN {printf("%.8f", decimal)}' </dev/null) # Make sure the fee rate is not in scientific notation
          ############ how can we verifiy that we got something back... error if naddad ################# can we still send without specifying the feerate????????????????????????

    # Calculate Weight
    UTXO_COUNT=$($BTC -rpcwallet=$WALLET listunspent 0 | grep txid | wc -l)
    COIN_COUNT=${#coins[@]}
    WEIGHT=$(( ((10 + (UTXO_COUNT * 41) + (COIN_COUNT * 34)) * 4) + (UTXO_COUNT * 105) ))

    # Calculate total fee (in $ATS)
    FEE_TOTAL=$(awk -v weight="$WEIGHT" -v feerate="$FEE_RATE" 'BEGIN {printf("%.0f", weight * feerate * 100000000 / 4000)}' </dev/null)

    # Calculate total (in $ATS)
    TOTAL=$(( (COIN_COUNT * AMOUNT_PER_COIN) + FEE_TOTAL ))

    echo "Summary:"
    echo "    Wallet Balance: $BALANCE"
    echo "    Number of Coins: ${#coins[@]}"
    echo "    \$ATS per Coin: $AMOUNT_PER_COIN"
    echo "    TX Estimated Weight (Max Block Size = 4,000,000 Units): $WEIGHT"
    echo "    Estimated Fee (\$ATS): $FEE_TOTAL"
    echo "    Total \$ATS: $TOTAL"
    echo "    Previous Chain Tip Confirmations: $($BTC -rpcwallet=$WALLET gettransaction $TXID_SATOSHI_COIN_CHAIN_TIP | jq .confirmations)"
    echo ""

    # Verify there is enough satoshis in the wallet
    if [[ $TOTAL -gt $BALANCE ]]; then
        echo "Error: Not enough satoshis in your wallet!"; exit 1
    fi

    # Verify it's a go with the user; prepare and send the transaction.
    read -p "Would you like to continue? (y|n): "
    if [[ "${REPLY}" = "y" || "${REPLY}" = "Y" ]]; then
		# Create string of coin outputs
		COIN_OUTPUTS=""
		for address in "${coins[@]}"; do
			COIN_OUTPUTS+=",{\"$address\":$AMOUNT_PER_COIN}"
		done

		# Send & capture the output to $OUTPUT
        OUTPUT=$($BTC -rpcwallet=$WALLET -named send estimate_mode=economical conf_target=$TARGET \
        outputs="[{\"$($BTC -rpcwallet=$WALLET getnewaddress)\":0.0001}$COIN_OUTPUTS]" \
        options="{\"change_position\":0,\"replaceable\":true,\"add_inputs\":true,\"inputs\":[{\"txid\":\"$TXID_SATOSHI_COIN_CHAIN_TIP\",\"vout\":0,\"sequence\":4294967293}]}")

        # Check for valid TXID; if valid, output to log.
        TXID=$(echo $OUTPUT | jq -r .txid)
        if [[ ${#TXID} -eq 64 && "$TXID" =~ ^[0-9a-fA-F]+$ ]]; then
            echo "LOAD: TXID:$TXID \$ATS:$TOTAL TIME:$(date +%s)" | sudo tee -a /var/log/$WALLET/log
        else
            echo $OUTPUT; exit 1
        fi
    fi

elif [[ $1 = "--destory" ]]; then # Bring a Satoshi Coins' chain to an end: TXID_SATOSHI_COIN_CHAIN_TIP

elif [[ $1 = "--log" ]]; then # Show log (/var/log/satoshicoins/log)
    #WALLET="satoshi_coins"
    WALLET="testing"
    cat /var/log/$WALLET/log

else
    $0 --help
    echo "Script Version 0.2"
fi



##CHAIN: 95a5b1a0787614d293907c871ac2b1f418d8ab415e7776793362e0e7579b000b - Satoshiware
##CHAIN: c3709e664bc6bf2d93d2eddaa715a7add8403365894826ede584191c3db1bad6 - BBOQC


##            echo "   DATE: $(date)" | sudo tee -a /var/log/$WALLET/log
##            echo "   ASCII DATA: \"$(echo $HEXSTRING | awk '{for(i=1;i<=length;i+=2) printf "%c", strtonum("0x"substr($0,i,2));}')\"" | sudo tee -a /var/log/$WALLET/log
            # Log "create "name" txid, blockheight, Regular time!!!! It's logging, but should it be different ????????????????????????????????????????????????????????????????????????
