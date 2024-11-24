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

      --send        Send funds (coins) from the (bank | mining) wallet
                    Parameters: ADDRESS  AMOUNT  WALLET  (PRIORITY)
                        Note: PRIORITY is optional (default = NORMAL). It helps determine the fee rate.
                              It can be set to NOW, NORMAL (6 hours), ECONOMICAL (1 day), or CHEAPSKATE (1 week).
                        Note: Enter '.' for the amount to empty the wallet completly (NORMAL priority is enforced)

      --bump        Bumps the fee of all (recent) outgoing transactions that are BIP 125 replaceable and not confirmed (bank and mining wallets only)
      --mining      Create new address to receive funds into the Mining wallet
      --bank        Create new address to receive funds into the Bank wallet
      --recent      Show recent (last 50) bank wallet transactions

    Satoshi Coins:
      --scoins      Create new address to receive funds into the Satoshi Coins wallet
      --create      Start new Satoshi Coins' chain (consolidates into single utxo): "NAME_OF_BANK_OPERATION"  (PRIORITY)
      --load        Load Satoshi Coins: AMOUNT_PER_COIN  (PRIORITY)
      --destroy     Bring the current Satoshi Coins' chain to an end: ADDRESS_FOR_REMAINING_WALLET_BALANCE  (PRIORITY)
                        Note: PRIORITY is optional (default = NORMAL). It helps determine the fee rate.
                              It can be set to NOW, NORMAL (6 hours), ECONOMICAL (1 day), or CHEAPSKATE (1 week).

      --log         Show log (/var/log/satoshicoins/log) and Satoshi Coins' chain tip transaction stat's

        Sample Chains:
            "BBOQC": c3709e664bc6bf2d93d2eddaa715a7add8403365894826ede584191c3db1bad6
            "Satoshiware": 95a5b1a0787614d293907c871ac2b1f418d8ab415e7776793362e0e7579b000b
            "BTC OF AZ": a8201d19dea0a03d453beb385482a8599eed91cfeb36e323ccb10a2e1e4aa617
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

    # Make sure satoshi coins' log file and corresponding directory exist
    if [[ ! -f /var/log/satoshi_coins/log ]]; then
        sudo mkdir -p /var/log/satoshi_coins
        sudo touch /var/log/satoshi_coins/log
        echo "Satoshi Coins Log Created: $(date)" | sudo tee -a /var/log/satoshi_coins/log
    fi

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

    # The wallet satoshi_coins is not allowed here!
    if [[ $WALLET == *"satoshi_coins"* ]]; then
        echo "Error! The wallet \"satoshi_coins\" is not allowed here!"; exit 1
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

    # Get Fee Rates (BTC / kB; SATS / vB) from full node
    BTC_FULL_NODE_IP=$(sudo cat /etc/bitcoin.conf | grep connect= | cut -d "=" -f 2) # Discover full node ipv4 from bitcoin config file
    if [[ ! "$BTC_FULL_NODE_IP" == *:* ]]; then  # Add default port if node was added
        BTC_FULL_NODE_IP="$BTC_FULL_NODE_IP:8332"
    fi
    FEE_RATE=$(curl -s --data-binary "{\"jsonrpc\":\"2.0\",\"id\":\"SCEstimateSmartFee\",\"method\":\"estimatesmartfee\",\"params\":[$TARGET]}" -H 'content-type:text/plain;' satoshi:satoshi@$BTC_FULL_NODE_IP | jq '.result.feerate')
    FEE_RATE_SATS_VB=$(awk -v decimal="$FEE_RATE" 'BEGIN {printf("%.8f", decimal * 100000)}' </dev/null)

    # Generate transacation
    $UNLOCK; $MINING_UNLOCK; OUTPUT=$($BTC -rpcwallet=$WALLET send "{\"$ADDRESS\": $AMOUNT}" null "unset" $FEE_RATE_SATS_VB "{\"replaceable\": true${SEND_ALL}}")

    # Check for valid TXID; if valid, ensure the tx was broadcasted
    TXID=$(echo $OUTPUT | jq -r .txid)
    if [[ ${#TXID} -eq 64 && "$TXID" =~ ^[0-9a-fA-F]+$ ]]; then
        #$BTC sendrawtransaction $($BTC -rpcwallet=satoshi_coins gettransaction $TXID | jq -r .hex) # Ensures tx is broadcasted if mempool is disabled
        echo $TXID
    else
        echo $OUTPUT
    fi

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

elif [[ $1 = "--create" ]]; then # Start new Satoshi Coins' chain (consolidates into single utxo)
    NAME_OF_BANK_OPERATION="${2^^}"; PRIORITY=${3,,} # Parameters: NAME_OF_BANK_OPERATION  (PRIORITY)

    HEXSTRING="5341544f53484920434f494e533a20" # ASCII HEX: "SATOSHI COINS: "

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
    if [[ $(($(grep -c "NEW_CHAIN" "/var/log/satoshi_coins/log") - $(grep -c "DELETE_CHAIN" "/var/log/satoshi_coins/log"))) -ne 0 ]]; then
        echo "Error! There is already an active chain!"
        tail /var/log/satoshi_coins/log -n 1
        exit 1
    fi

    # Prepare and send the transaction; it will also combine all CONFIRMED utxos into one.
    read -p "Creating new Chain: \"$NAME_OF_BANK_OPERATION\". Would you like to continue? (y|n): "
    if [[ "${REPLY}" = "y" || "${REPLY}" = "Y" ]]; then
        # Get Fee Rates (BTC / kB; SATS / vB) from full node
        BTC_FULL_NODE_IP=$(sudo cat /etc/bitcoin.conf | grep connect= | cut -d "=" -f 2) # Discover full node ipv4 from bitcoin config file
        if [[ ! "$BTC_FULL_NODE_IP" == *:* ]]; then  # Add default port if node was added
            BTC_FULL_NODE_IP="$BTC_FULL_NODE_IP:8332"
        fi
        FEE_RATE=$(curl -s --data-binary "{\"jsonrpc\":\"2.0\",\"id\":\"SCEstimateSmartFee\",\"method\":\"estimatesmartfee\",\"params\":[$TARGET]}" -H 'content-type:text/plain;' satoshi:satoshi@$BTC_FULL_NODE_IP | jq '.result.feerate')
        FEE_RATE_SATS_VB=$(awk -v decimal="$FEE_RATE" 'BEGIN {printf("%.8f", decimal * 100000)}' </dev/null)

        HEXSTRING="${HEXSTRING}$(echo -n $NAME_OF_BANK_OPERATION | od -An -tx1 | sed 's/ //g' | sed ':a;N;$!ba;s/\n//g')"
        $SATOSHI_COINS_UNLOCK
        OUTPUT=$($BTC -rpcwallet=satoshi_coins -named send fee_rate=$FEE_RATE_SATS_VB \
        outputs="[{\"$($BTC -rpcwallet=satoshi_coins getnewaddress)\":$($BTC -rpcwallet=satoshi_coins getbalance)},{\"data\":\"$HEXSTRING\"}]" \
        options="{\"change_position\":0,\"replaceable\":true,\"subtract_fee_from_outputs\":[0]}")

        # Check for valid TXID; if valid, output to log and ensure the tx was broadcasted
        TXID=$(echo $OUTPUT | jq -r .txid)
        if [[ ${#TXID} -eq 64 && "$TXID" =~ ^[0-9a-fA-F]+$ ]]; then
            #$BTC sendrawtransaction $($BTC -rpcwallet=satoshi_coins gettransaction $TXID | jq -r .hex) # Ensures tx is broadcasted if mempool is disabled
            echo "NEW_CHAIN: TXID:$TXID TIME:$(date +%s) DATA:$HEXSTRING NAME:\"$NAME_OF_BANK_OPERATION\"" | sudo tee -a /var/log/satoshi_coins/log
        else
            echo $OUTPUT; exit 1
        fi
    fi

elif [[ $1 = "--load" ]]; then # Load Satoshi Coins
    AMOUNT_PER_COIN=$2; PRIORITY=${3,,} # Parameters: AMOUNT_PER_COIN  (PRIORITY)

    # Input Checking
    if [[ -z $AMOUNT_PER_COIN ]]; then
        echo "Error! Insufficient Parameters!"; exit 1
    fi

    # Check the logs to verify the chain is active
    if [[ $(($(grep -c "NEW_CHAIN" "/var/log/satoshi_coins/log") - $(grep -c "DELETE_CHAIN" "/var/log/satoshi_coins/log"))) -eq 0 ]]; then
        echo "Error! There is no active chain!"; exit 1
    fi

    # Get the tip of the Satoshi Coins' Chain
    TXID_SATOSHI_COIN_CHAIN_TIP=$(tac /var/log/satoshi_coins/log | grep -m 1 -E "NEW_CHAIN|LOAD" | cut -d " " -f 2)
    TXID_SATOSHI_COIN_CHAIN_TIP=${TXID_SATOSHI_COIN_CHAIN_TIP:5}
    if ! [[ ${#TXID_SATOSHI_COIN_CHAIN_TIP} -eq 64 && "$TXID_SATOSHI_COIN_CHAIN_TIP" =~ ^[0-9a-fA-F]+$ ]]; then
        echo "Error! Invalid Chain tip TXID (${TXID_SATOSHI_COIN_CHAIN_TIP})!"; exit 1
    fi

    # Verify TXID has an unspent utxo on the first output
    if [[ -z $($BTC -rpcwallet=satoshi_coins listunspent 0 | grep $TXID_SATOSHI_COIN_CHAIN_TIP -A 1 | grep "vout\": 0") ]]; then
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
        if [[ "$user_input" == "done" ]]; then
            break
        elif [[ -z "$user_input" ]]; then
            continue
        fi

        # Remove any text after the address
        user_input=$(echo "$user_input" | cut -d " " -f 1)

        # Convert the input to lowercase
        user_input=$(echo "$user_input" | tr 'A-Z' 'a-z')

        # Check if the coin address is valid (bech32)
        if [[ $($BTC validateaddress $user_input 2> /dev/null | jq .isvalid ) != "true" ]]; then
            echo "Error: Invalid address!"; continue
        fi

        # Check if the input is a duplicate
        if [[ -n "${coins[$user_input]}" ]]; then
            echo "Error: This address has already been entered."; continue
        fi

        coins["$user_input"]=1 # Store the valid input in the associative array (key is the input string)
    done

    # Get wallet balance (in $ATS)
    BALANCE=$(awk -v balance="$($BTC -rpcwallet=satoshi_coins getbalance)" 'BEGIN {printf("%.0f", balance * 100000000)}' </dev/null)

    # Get Fee Rates (BTC / kB; SATS / vB) from full node
    BTC_FULL_NODE_IP=$(sudo cat /etc/bitcoin.conf | grep connect= | cut -d "=" -f 2) # Discover full node ipv4 from bitcoin config file
    if [[ ! "$BTC_FULL_NODE_IP" == *:* ]]; then  # Add default port if node was added
        BTC_FULL_NODE_IP="$BTC_FULL_NODE_IP:8332"
    fi
    FEE_RATE=$(curl -s --data-binary "{\"jsonrpc\":\"2.0\",\"id\":\"SCEstimateSmartFee\",\"method\":\"estimatesmartfee\",\"params\":[$TARGET]}" -H 'content-type:text/plain;' satoshi:satoshi@$BTC_FULL_NODE_IP | jq '.result.feerate')
    FEE_RATE=$(awk -v decimal="$FEE_RATE" 'BEGIN {printf("%.8f", decimal)}' </dev/null) # Make sure the fee rate is not in scientific notation
    FEE_RATE_SATS_VB=$(awk -v decimal="$FEE_RATE" 'BEGIN {printf("%.8f", decimal * 100000)}' </dev/null)

    # Calculate Weight
    UTXO_COUNT=$($BTC -rpcwallet=satoshi_coins listunspent 0 | grep txid | wc -l)
    COIN_COUNT=${#coins[@]}
    WEIGHT=$(( ((10 + (UTXO_COUNT * 41) + (COIN_COUNT * 34)) * 4) + (UTXO_COUNT * 105) ))

    # Calculate total fee (in $ATS)
    FEE_TOTAL=$(awk -v weight="$WEIGHT" -v feerate="$FEE_RATE" 'BEGIN {printf("%.0f", weight * feerate * 100000000 / 4000)}' </dev/null)

    # Calculate total (in $ATS)
    TOTAL=$(( (COIN_COUNT * AMOUNT_PER_COIN) ))

    echo ""; echo "Summary:"
    echo "    Wallet Balance: $BALANCE \$ATS"
    echo "    Number of Coins: ${#coins[@]}"
    echo "    \$ATS per Coin: $AMOUNT_PER_COIN \$ATS"
    echo "    TX Estimated Weight (Max Block Size = 4,000,000 Units): $WEIGHT Units"
    echo "    Estimated Fee: $FEE_TOTAL \$ATS"
    echo "    Total: $TOTAL \$ATS"
    echo "    Confirmations of Previous Chain Tip: $($BTC -rpcwallet=satoshi_coins gettransaction $TXID_SATOSHI_COIN_CHAIN_TIP | jq .confirmations)"; echo ""

    # Verify there is enough satoshis in the wallet
    if [[ $(($TOTAL + $FEE_TOTAL + 1000)) -gt $BALANCE ]]; then
        echo "Error: Not enough satoshis in your wallet!"; exit 1
    fi

    # Verify it's a go with the user; prepare and send the transaction
    read -p "Would you like to continue? (y|n): "
    if [[ "${REPLY}" = "y" || "${REPLY}" = "Y" ]]; then
        # Convert $AMOUNT_PER_COIN from SATS to BTC
        AMOUNT_PER_COIN=$(awk -v sats="$AMOUNT_PER_COIN" 'BEGIN {printf("%.8f", sats / 100000000)}' </dev/null)

        # Create string of coin outputs
        COIN_OUTPUTS=""
        for address in "${!coins[@]}"; do
            COIN_OUTPUTS+=",{\"$address\":$AMOUNT_PER_COIN}"
        done

        # Calculate remaining balance (in BTC) after this transaction
        REMAINDER=$(awk -v remain_sats="$(( $BALANCE - $TOTAL ))" 'BEGIN {printf("%.8f", remain_sats / 100000000)}' </dev/null)

        # Send & capture the output to $OUTPUT
        $SATOSHI_COINS_UNLOCK
        OUTPUT=$($BTC -rpcwallet=satoshi_coins -named send fee_rate=$FEE_RATE_SATS_VB \
        outputs="[{\"$($BTC -rpcwallet=satoshi_coins getnewaddress)\":$REMAINDER}$COIN_OUTPUTS]" \
        options="{\"change_position\":0,\"replaceable\":true,\"add_inputs\":true,\"inputs\":[{\"txid\":\"$TXID_SATOSHI_COIN_CHAIN_TIP\",\"vout\":0,\"sequence\":4294967293}]}")

        # Check for valid TXID; if valid, output to log and ensure the tx was broadcasted
        TXID=$(echo $OUTPUT | jq -r .txid)
        if [[ ${#TXID} -eq 64 && "$TXID" =~ ^[0-9a-fA-F]+$ ]]; then
            #$BTC sendrawtransaction $($BTC -rpcwallet=satoshi_coins gettransaction $TXID | jq -r .hex) # Ensures tx is broadcasted if mempool is disabled
            echo "LOAD: TXID:$TXID TIME:$(date +%s) \$ATS:$TOTAL" | sudo tee -a /var/log/satoshi_coins/log
            for address in "${!coins[@]}"; do # log each coin
                echo "    $address: $AMOUNT_PER_COIN BTC" | sudo tee -a /var/log/satoshi_coins/log
            done
        else
            echo $OUTPUT; exit 1
        fi
    fi

elif [[ $1 = "--destroy" ]]; then # Bring the current Satoshi Coins' chain to an end
    ADDRESS_FOR_REMAINING_WALLET_BALANCE=$2; PRIORITY=${3,,} # Parameters: ADDRESS_FOR_REMAINING_WALLET_BALANCE (PRIORITY)

    # Input Checking
    if [[ -z $ADDRESS_FOR_REMAINING_WALLET_BALANCE ]]; then
        echo "Error! Insufficient Parameters!"; exit 1
    fi

    # Validate address ADDRESS_FOR_REMAINING_WALLET_BALANCE
    if [[ $($BTC validateaddress $ADDRESS_FOR_REMAINING_WALLET_BALANCE | jq '.isvalid') != "true" ]]; then
        echo "Error! Address provided is not valid!"; exit 1
    fi

    # Check the logs to verify there is active chain to destroy
    if [[ $(( $(grep -c "NEW_CHAIN" "/var/log/satoshi_coins/log") - $(grep -c "DELETE_CHAIN" "/var/log/satoshi_coins/log") )) -eq 0 ]]; then
        echo "Error! There is no active chain to destroy!"; exit 1
    fi

    # Get the tip of the Satoshi Coins' Chain
    TXID_SATOSHI_COIN_CHAIN_TIP=$(tac /var/log/satoshi_coins/log | grep -m 1 -E "NEW_CHAIN|LOAD" | cut -d " " -f 2)
    TXID_SATOSHI_COIN_CHAIN_TIP=${TXID_SATOSHI_COIN_CHAIN_TIP:5}
    if ! [[ ${#TXID_SATOSHI_COIN_CHAIN_TIP} -eq 64 && "$TXID_SATOSHI_COIN_CHAIN_TIP" =~ ^[0-9a-fA-F]+$ ]]; then
        echo "Error! Invalid Chain tip TXID (${TXID_SATOSHI_COIN_CHAIN_TIP})!"; exit 1
    fi

    # Verify TXID has an unspent utxo on the first output
    if [[ -z $($BTC -rpcwallet=satoshi_coins listunspent 0 | grep $TXID_SATOSHI_COIN_CHAIN_TIP -A 1 | grep "vout\": 0") ]]; then
        echo "Error! The Chain Tip TXID has no unspent utxo @ index 0! It's already destroyed!"; exit 1
    fi

    # Make sure there are at least two utxos (two are required to create a transaction that "destroys" a chain)
    if [[ $($BTC -rpcwallet=satoshi_coins listunspent 0 | grep txid | wc -l) -lt 2 ]]; then
        echo "Error! Not enough utxos in Satoshi Coins' wallet! Needs at least two"; exit 1
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

    # Verify it's a go with the user; prepare and send the transaction.
    read -p "WARNING! You are about to destory an active Satoshi Coins' chain! Would you like to continue? (yes|n): "
    if [[ "${REPLY,,}" = "yes" ]]; then
        # Find the first utxo that does not represent the Satoshi Coins' chain
        txids=($($BTC -rpcwallet=satoshi_coins listunspent 0 | jq -r '.[].txid'))
        vouts=($($BTC -rpcwallet=satoshi_coins listunspent 0 | jq -r '.[].vout'))
        for i in "${!txids[@]}"; do
            if [[ ${vouts[$i]} -ne 0 || $TXID_SATOSHI_COIN_CHAIN_TIP != ${txids[$i]} ]]; then
                D_TXID=${txids[$i]}
                D_VOUT=${vouts[$i]}
                break;
            fi
        done

        # Get Fee Rates (BTC / kB; SATS / vB) from full node
        BTC_FULL_NODE_IP=$(sudo cat /etc/bitcoin.conf | grep connect= | cut -d "=" -f 2) # Discover full node ipv4 from bitcoin config file
        if [[ ! "$BTC_FULL_NODE_IP" == *:* ]]; then  # Add default port if node was added
            BTC_FULL_NODE_IP="$BTC_FULL_NODE_IP:8332"
        fi
        FEE_RATE=$(curl -s --data-binary "{\"jsonrpc\":\"2.0\",\"id\":\"SCEstimateSmartFee\",\"method\":\"estimatesmartfee\",\"params\":[$TARGET]}" -H 'content-type:text/plain;' satoshi:satoshi@$BTC_FULL_NODE_IP | jq '.result.feerate')
        FEE_RATE_SATS_VB=$(awk -v decimal="$FEE_RATE" 'BEGIN {printf("%.8f", decimal * 100000)}' </dev/null)

        # Create a transaction with two inputs where the utxo for the Satoshi Coins' chain tip is used as the second one.
        $SATOSHI_COINS_UNLOCK
        OUTPUT=$($BTC -rpcwallet=satoshi_coins -named send fee_rate=$FEE_RATE_SATS_VB \
        outputs="[{\"$ADDRESS_FOR_REMAINING_WALLET_BALANCE\":$($BTC -rpcwallet=satoshi_coins getbalance)}]" \
        options="{\"replaceable\":true,\"add_inputs\":true,\"inputs\":[{\"txid\":\"$D_TXID\",\"vout\":$D_VOUT,\"sequence\":4294967293},{\"txid\":\"$TXID_SATOSHI_COIN_CHAIN_TIP\",\"vout\":0,\"sequence\":4294967293}],\"subtract_fee_from_outputs\":[0]}")

        # Check for valid TXID; if valid, output to log and ensure the tx was broadcasted
        TXID=$(echo $OUTPUT | jq -r .txid)
        if [[ ${#TXID} -eq 64 && "$TXID" =~ ^[0-9a-fA-F]+$ ]]; then
            #$BTC sendrawtransaction $($BTC -rpcwallet=satoshi_coins gettransaction $TXID | jq -r .hex) # Ensures tx is broadcasted if mempool is disabled
            echo "DELETE_CHAIN: TXID:$TXID TIME:$(date +%s)" | sudo tee -a /var/log/satoshi_coins/log
        else
            echo $OUTPUT; exit 1
        fi
    else
        echo "Aborted!"
    fi

elif [[ $1 = "--log" ]]; then # Show log (/var/log/satoshicoins/log) and Satoshi Coins' chain tip transaction stat's
    cat /var/log/satoshi_coins/log; echo ""

    # Get the last transacation on the latest Satoshi Coins' chain
    LAST_TXID=$(tac /var/log/satoshi_coins/log | grep -m 1 -E "NEW_CHAIN|LOAD|DELETE_CHAIN" | cut -d " " -f 2)
    LAST_TXID=${LAST_TXID:5}

    # Report the number of utxos in the "satoshi_coins" wallet
    echo "The \"satoshi_coins\" Wallet UTXO Count: $($BTC -rpcwallet=satoshi_coins listunspent 0 | grep -c txid)"

    # Report if there is an active chain or not
    if [[ $(( $(grep -c "NEW_CHAIN" "/var/log/satoshi_coins/log") - $(grep -c "DELETE_CHAIN" "/var/log/satoshi_coins/log") )) -eq 0 ]]; then
        echo "There is no active chain..."
    else
        echo "Current Chain Tip: $LAST_TXID"

        # Verify the Chain Tip's TXID output @ index 0 has NOT been spent
        if [[ -z $($BTC -rpcwallet=satoshi_coins listunspent 0 | grep $LAST_TXID -A 1 | grep "vout\": 0") ]]; then
            echo "Error! The Chain Tip's TXID output @ index 0 has been spent!"
        fi
    fi

    # Exit if there is no TXID (i.e. virgin log file)
    if [[ -z $LAST_TXID ]]; then exit; fi

    # Show Chain Tip's TX Details
    echo "Chain Tip's TX Details:"
    $BTC -rpcwallet=satoshi_coins gettransaction $LAST_TXID | grep -m 1 amount
    $BTC -rpcwallet=satoshi_coins gettransaction $LAST_TXID | grep -m 1 fee
    $BTC -rpcwallet=satoshi_coins gettransaction $LAST_TXID | jq \
        'del(.amount, .fee, .blockhash, .blockindex, .blocktime, .txid, .walletconflicts, .time, .hex, .timereceived, .details)' | tr -d '()[]{},' | sed '/^\s*$/d'
    $BTC decoderawtransaction $($BTC -rpcwallet=satoshi_coins gettransaction $LAST_TXID | jq -r .hex) | jq \
        'del(.txid, .hash, .version, .locktime, .vout, .vin[].scriptSig, .vin[].txinwitness)' | tr -d '()[]{},' | sed '/^\s*$/d'
    echo "  \"vout\":"
    $BTC decoderawtransaction $($BTC -rpcwallet=satoshi_coins gettransaction $LAST_TXID | jq -r .hex) | jq .vout | jq \
        'del(.[].scriptPubKey.asm, .[].scriptPubKey.desc, .[].scriptPubKey.hex, .[].scriptPubKey.type)' | tr -d '()[]{},' | sed '/scriptPubKey"/d' | sed '/^\s*$/d' | sed 's/^/  /'
    $BTC decoderawtransaction $($BTC -rpcwallet=satoshi_coins gettransaction $LAST_TXID | jq -r .hex) | grep nulldata -B 3 | grep "asm\|nulldata"

else
    $0 --help
    echo "Script Version 0.38"
fi