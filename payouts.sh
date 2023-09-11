#!/bin/bash

# Make sure we are not running as root, but that we have sudo privileges.
if [ "$(id -u)" = "0" ]; then
   echo "This script must NOT be run as root (or with sudo)!"
   exit 1
elif [ "$(sudo -l | grep '(ALL : ALL) ALL' | wc -l)" = 0 ]; then
   echo "You do not have enough sudo privileges!"
   exit 1
fi

# Create the file with the needed envrionment variables if it has not been already
if [ ! -f /etc/default/payouts.env ]; then
    cat << EOF | sudo tee /etc/default/_payouts.env > /dev/null
NETWORK=""                      # Example: "AZ Money"
CLARIFY=""                      # Leave blank; variable is used in the core customer contract email notification to clarify difference names (see Deseret Money)
NETWORKPREFIX=""                # Example: "AZ"
DENOMINATION=""                 # Example: "SAGZ"
DENOMINATIONNAME=""             # Example: "saguaros"
EXPLORER=""                     # Example: "<a href=https://somemicrocurrency.com/explorer><u>Some microcurrency Explorer</u></a>"

API=""                          # API address (e.g. "https://api.brevo.com/v3/smtp/email"
KEY=""                          # API key to send email (e.g. "xkeysib-05...76-9...1")

SENDEREMAIL=""                  # Sender email (e.g. satoshi@somemicrocurrency.com)

INITIALREWARD=                  # Initial block subsidy (e.g. 1500000000)
EPOCHBLOCKS=                    # Number of blocks before each difficulty adjustment (e.g. 1440)
HALVINGINTERVAL=                # Number of blocks in before the next halving (e.g. 262800)
HASHESPERCONTRACT=              # Hashes per second for each contract (e.g. 10000000000)
BLOCKINTERVAL=                  # Number of seconds (typically) between blocks (e.g. 120)

TX_BATCH_SZ=                    # Number of outputs for each send transaction (e.g. 10)

ADMINISTRATOREMAIL=""           # Administrator email (e.g. your_email@somedomain.com)
EOF

    echo "Assign static values to all the variables in the \"/etc/default/_payouts.env\" file"
    echo "Rename file to \"payouts.env\" (from \"_payouts.env\") when finished"
    exit 0
fi

# Make sure the send_email routine is installed
if ! command -v send_email &> /dev/null; then
    echo "Error! The \"send_email\" routine could not be found!" | sudo tee -a $LOG
    echo "Download the script and execute \"./send_email.sh --install\" to install this routine."
    read -p "Press any enter to continue ..."
fi

# Load envrionment variables and then verify
source /etc/default/payouts.env
if [[ -z $INITIALREWARD || -z $EPOCHBLOCKS || -z $HALVINGINTERVAL || -z $HASHESPERCONTRACT || -z $BLOCKINTERVAL || -z $NETWORK || -z $NETWORKPREFIX || -z $DENOMINATION || -z $DENOMINATIONNAME || -z $EXPLORER || -z $API || -z $KEY ]]; then
    echo ""; echo "Error! Not all variables have assignments in the \"/etc/default/payouts.env\" file"
    sudo rm /etc/default/payouts.env; echo "File \"/etc/default/payouts.env\" has been deleted!"; echo ""
    $0 # Rerun this script creating new "_payouts.env" file
fi

# Universal envrionment variables
BTC=$(cat /etc/bash.bashrc | grep "alias btc=" | cut -d "\"" -f 2)
UNLOCK="$BTC -rpcwallet=bank walletpassphrase $(sudo cat /root/passphrase) 600"

# Database Location and development mode
SQ3DBNAME=/var/lib/btcofaz.db
LOG=/var/log/payout.log
SQ3DBNAME=/var/lib/btcofaz.db.development # Uncomment this line to switch to the development database.
if [[ $SQ3DBNAME == *"development"* ]]; then
    LOG=~/log.payout
    echo ""; echo "log file is located at \"~/log.payout\""
    echo ""; echo "Did you make a recent copy of the production database for development mode?"
    echo "\"sudo cp /var/lib/btcofaz.db /var/lib/btcofaz.db.development\""
    echo ""; echo "Did you make backups of the production database?"
    echo "\"sudo cp /var/lib/btcofaz.db /var/lib/btcofaz.db.bak(1, 2, 3...)\""
    echo ""; read -p "You are in development mode! Press any enter to continue ..."
fi

# See which payouts parameter was passed and execute accordingly
if [[ $1 = "-h" || $1 = "--help" ]]; then # Show all possible paramters
    cat << EOF
    Options:
      -h, --help        Display this help message and exit
      -i, --install     Install this script (payouts) in /usr/local/sbin, the DB if it hasn't been already, and load available epochs from the blockchain
      -e, --epoch       Look for next difficulty epoch and prepare the DB for next round of payouts
      -s, --send        Send the Money (a 2nd NUMBER parameter generates NUMBER of outputs; default = 1)
      -c, --confirm     Confirm the sent payouts are confirmed in the blockchain; update the DB
      -m, --email       Prepare all core customer notification emails for the latest epoch
      -d, --dump        Show all the contents of the database
      -a, --accounts    Show all accounts
      -l, --sales       Show all sales
      -r, --contracts   Show all contracts
      -x, --txs         Show all the transactions associated with the latest payout
      -p, --payouts     Show all payouts thus far
      -t, --totals      Show total amounts for each contract (identical addresses are combinded)
      --add-user        Add a new account
      --disable-user    Disable an account (i.e. "deletes" an account, disables associated contracts, but retains its critical data)
      --add-sale        Add a sale
      --update-sale     Update sale status
      --add-contr       Add a contract
      --update-contr    Mark a contract as delivered
      --disable-contr   Disable a contract
EOF
elif [[ $1 = "-i" || $1 = "--install" ]]; then # Install this script in /usr/local/sbin, the DB if it hasn't been already, and load available epochs from the blockchain
    echo "Installing this script (payouts) in /usr/local/sbin/"
    if [ ! -f /usr/local/sbin/payouts ]; then
        sudo cat $0 | sed '/Install this script (payouts)/d' | sed '/SQ3DBNAME=\/var\/lib\/btcofaz.db.development /d' | sudo tee /usr/local/sbin/payouts > /dev/null
        sudo sed -i 's/$1 = "-i" || $1 = "--install"/"a" = "b"/' /usr/local/sbin/payouts # Make it so this code won't run again in the newly installed script.
        sudo chmod +x /usr/local/sbin/payouts
    else
        echo "\"payouts\" already exists in /usr/local/sbin!"
        read -p "Would you like to uninstall it? (y|n): "
        if [[ "${REPLY}" = "y" || "${REPLY}" = "Y" ]]; then
            sudo rm /usr/local/sbin/payouts
            exit 0
        fi
    fi

    SQ3DBNAME=/var/lib/btcofaz.db # Make sure it using the production (not the development) database
    if [ -f "$SQ3DBNAME" ]; then
        echo "\"$SQ3DBNAME\" Already Exists!"
        exit 0
    fi

    sudo apt-get -y install sqlite3

    sudo sqlite3 $SQ3DBNAME << EOF
    CREATE TABLE accounts (
        account_id INTEGER PRIMARY KEY,
        master INTEGER,
        contact INTEGER NOT NULL,
        first_name TEXT NOT NULL,
        last_name TEXT,
        preferred_name TEXT,
        email TEXT NOT NULL UNIQUE,
        phone TEXT,
        disabled INTEGER) /* FALSE = 0 or NULL; TRUE = 1 */
EOF

    sudo sqlite3 $SQ3DBNAME << EOF
    CREATE TABLE sales (
        sale_id INTEGER PRIMARY KEY,
        account_id INTEGER NOT NULL, /* This is who is/was accountable for the payment; it may vary from the account_id on the corresponding contracts. */
        time INTEGER NOT NULL,
        quantity INTEGER NOT NULL,
        status INTEGER, /* NOT_PAID = 0 or NULL; PAID = 1; TRIAL = 2; DISABLED = 3 */
        FOREIGN KEY (account_id) REFERENCES accounts (account_id) ON DELETE CASCADE)
EOF

    sudo sqlite3 $SQ3DBNAME << EOF
    CREATE TABLE contracts (
        contract_id INTEGER PRIMARY KEY,
        account_id INTEGER NOT NULL,
        sale_id INTEGER,
        quantity INTEGER NOT NULL,
        time INTEGER NOT NULL,
        active INTEGER, /* Deprecated = 0; Active = 1 or NULL; Opened = 2 */
        delivered INTEGER, /* NO = 0 or NULL; YES = 1 */
        micro_address TEXT NOT NULL,
        FOREIGN KEY (account_id) REFERENCES accounts (account_id) ON DELETE CASCADE,
        FOREIGN KEY (sale_id) REFERENCES sales (sale_id) ON DELETE CASCADE)
EOF

    sudo sqlite3 $SQ3DBNAME << EOF
    CREATE TABLE payouts (
        epoch_period INTEGER PRIMARY KEY,
        block_height INTEGER NOT NULL,
        subsidy INTEGER NOT NULL,
        total_fees INTEGER NOT NULL,
        block_time INTEGER NOT NULL,
        difficulty REAL NOT NULL,
        amount INTEGER NOT NULL,
        notified INTEGER, /* Have the emails been prepared for the core customers? FALSE = 0 or NULL; TRUE = 1*/
        satrate INTEGER)
EOF

    sudo sqlite3 $SQ3DBNAME << EOF
    CREATE TABLE txs (
        tx_id INTEGER PRIMARY KEY,
        contract_id INTEGER NOT NULL,
        epoch_period INTEGER NOT NULL,
        txid BLOB,
        vout INTEGER,
        amount INTEGER NOT NULL,
        block_height INTEGER,
        FOREIGN KEY (contract_id) REFERENCES contracts (contract_id),
        FOREIGN KEY (epoch_period) REFERENCES payouts (epoch_period))
EOF

    # Configure bitcoind's Log Files; Prevents them from Filling up the Partition
    sudo touch /var/log/payout.log
    sudo chown root:root /var/log/payout.log
    sudo chmod 644 /var/log/payout.log
    cat << EOF | sudo tee /etc/logrotate.d/payout
/var/log/payout.log {
$(printf '\t')create 644 root root
$(printf '\t')monthly
$(printf '\t')rotate 6
$(printf '\t')compress
$(printf '\t')delaycompress
$(printf '\t')postrotate
$(printf '\t')endscript
}
EOF

    # Insert payout for genesis block
    tmp=$($BTC getblock $($BTC getblockhash 0))
    sudo sqlite3 $SQ3DBNAME "INSERT INTO payouts (epoch_period, block_height, subsidy, total_fees, block_time, difficulty, amount, notified, satrate) VALUES (0, 0, $INITIALREWARD, 0, $(echo $tmp | jq '.time'), $(echo $tmp | jq '.difficulty'), 0, 1, NULL);"

    # Load all payout periods thus far
    while [ -z $output ]; do
        output=$($0 -e 2> /dev/null | grep "next epoch"); i=$((i + 1))
        echo "Finished loading epoch period number $i into the payout table"
    done

    # Set all payout amounts to 0 and notified flag to 1
    sudo sqlite3 $SQ3DBNAME "UPDATE payouts SET amount = 0, notified = 1"

    # Show the user their new database
    echo ""
    sqlite3 $SQ3DBNAME ".dump"

elif [[ $1 = "-e" || $1 = "--epoch" ]]; then # Look for next difficulty epoch and prepare the DB for next round of payouts
    # echo $SQ3DBNAME
    # sudo sqlite3 $SQ3DBNAME "DELETE FROM txs WHERE epoch_period = (SELECT MAX(epoch_period) FROM payouts);"
    # sudo sqlite3 $SQ3DBNAME "DELETE FROM payouts WHERE epoch_period = (SELECT MAX(epoch_period) FROM payouts);"
    NEXTEPOCH=$((1 + $(sqlite3 $SQ3DBNAME "SELECT epoch_period FROM payouts ORDER BY epoch_period DESC LIMIT 1;")))
    BLOCKEPOCH=$((NEXTEPOCH * EPOCHBLOCKS))

    if [ $($BTC getblockcount) -ge $BLOCKEPOCH ]; then # See if it is time for the next payout
        # Find total fees for the epoch period
        TOTAL_FEES=0; TX_COUNT=0; TOTAL_WEIGHT=0; MAXFEERATE=0
        for ((i = $(($BLOCKEPOCH - $EPOCHBLOCKS)); i < $BLOCKEPOCH; i++)); do
            tmp=$($BTC getblockstats $i)
            TOTAL_FEES=$(($TOTAL_FEES + $(echo $tmp | jq '.totalfee')))
            TX_COUNT=$(($TX_COUNT + $(echo $tmp | jq '.txs') - 1))
            TOTAL_WEIGHT=$(($TOTAL_WEIGHT + $(echo $tmp | jq '.total_weight')))
            if [ $MAXFEERATE -lt $(echo $tmp | jq '.maxfeerate') ]; then
                MAXFEERATE=$(echo $tmp | jq '.maxfeerate')
            fi
            echo "BLOCK: $i, TOTAL_FEES: $TOTAL_FEES, TX_COUNT: $TX_COUNT, TOTAL_WEIGHT: $TOTAL_WEIGHT, MAXFEERATE: $MAXFEERATE"
        done
        echo "$(date) - Fee calculation complete for next epoch (Number $NEXTEPOCH) - TOTAL_FEES: $TOTAL_FEES, TX_COUNT: $TX_COUNT, TOTAL_WEIGHT: $TOTAL_WEIGHT, MAXFEERATE: $MAXFEERATE" | sudo tee -a $LOG

        # Get details (time and difficulty) of the epoch block
        tmp=$($BTC getblock $($BTC getblockhash $BLOCKEPOCH))
        BLOCKTIME=$(echo $tmp | jq '.time')
        DIFFICULTY=$(echo $tmp | jq '.difficulty')

        # Calculate subsidy
        EXPONENT=$(awk -v eblcks=$BLOCKEPOCH -v interval=$HALVINGINTERVAL 'BEGIN {printf("%d\n", eblcks / interval)}')
        SUBSIDY=$(awk -v reward=$INITIALREWARD -v expo=$EXPONENT 'BEGIN {printf("%d\n", reward / 2 ^ expo)}')

        # Calculate payout amount
        AMOUNT=$(awk -v hashrate=$HASHESPERCONTRACT -v btime=$BLOCKINTERVAL -v subs=$SUBSIDY -v totalfee=$TOTAL_FEES -v diff=$DIFFICULTY -v eblcks=$EPOCHBLOCKS 'BEGIN {printf("%d\n", ((hashrate * btime) / (diff * 2^32)) * ((subs * eblcks) + totalfee))}')

        # Get array of contract_ids (from active contracts only before this epoch).
        tmp=$(sqlite3 $SQ3DBNAME "SELECT contract_id, quantity FROM contracts WHERE active != 0 AND time<=$BLOCKTIME")
        eol=$'\n'; read -a query <<< ${tmp//$eol/ }

        # Create individual arrays for each column
        read -a CONTIDS <<< ${query[*]%|*}
        read -a QTYS <<< ${query[*]#*|}

        # Prepare values to INSERT into the sqlite db.
        SQL_VALUES=""
        for ((i=0; i<${#QTYS[@]}; i++)); do
            OUTPUT=$(awk -v qty=${QTYS[i]} -v amnt=$AMOUNT 'BEGIN {printf("%d\n", (qty * amnt))}')
            SQL_VALUES="$SQL_VALUES(${CONTIDS[i]}, $NEXTEPOCH, $OUTPUT),"
        done
        SQL_VALUES="${SQL_VALUES%?}"

        # Insert into database
        echo "$(date) - Attempting to insert next epoch (Number $NEXTEPOCH) into DB" | sudo tee -a $LOG
        sudo sqlite3 -bail $SQ3DBNAME << EOF
        BEGIN transaction;
        PRAGMA foreign_keys = ON;
        INSERT INTO payouts (epoch_period, block_height, subsidy, total_fees, block_time, difficulty, amount)
        VALUES ($NEXTEPOCH, $BLOCKEPOCH, $SUBSIDY, $TOTAL_FEES, $BLOCKTIME, $DIFFICULTY, $AMOUNT);
        INSERT INTO txs (contract_id, epoch_period, amount)
        VALUES $SQL_VALUES;
        COMMIT;
EOF

        # Query DB
        echo ""; sqlite3 $SQ3DBNAME ".mode columns" "SELECT epoch_period, block_height, subsidy, total_fees, block_time, difficulty, amount FROM payouts WHERE epoch_period = $NEXTEPOCH" "SELECT * FROM txs WHERE epoch_period = $NEXTEPOCH"; echo ""
        t_payout=$(sqlite3 -separator '; ' $SQ3DBNAME "SELECT 'Epoch Period: ' || epoch_period, 'Epoch Block: ' || block_height, 'Block Time: ' || datetime(block_time, 'unixepoch', 'localtime') as dates, 'Difficulty: ' || difficulty, 'Payout: ' || printf('%.8f', (CAST(amount AS REAL) / 100000000)), 'Subsidy: ' || printf('%.8f', (CAST(subsidy AS REAL) / 100000000)), 'Blocks: ' || (block_height - $EPOCHBLOCKS) || ' - ' || (block_height - 1), 'Total Fees: ' || printf('%.8f', (CAST(total_fees AS REAL) / 100000000)) FROM payouts WHERE epoch_period = $NEXTEPOCH")
        payout_amount=$(sqlite3 $SQ3DBNAME "SELECT amount FROM payouts WHERE epoch_period = $NEXTEPOCH")
        qty_contracts=$(sqlite3 $SQ3DBNAME "SELECT SUM(quantity) FROM contracts WHERE active != 0 AND time<=$BLOCKTIME")
        qty_utxo=$(sqlite3 $SQ3DBNAME "SELECT COUNT(*) FROM txs WHERE epoch_period = $NEXTEPOCH")
        total_payment=$(sqlite3 $SQ3DBNAME "SELECT printf('%.8f', (CAST(SUM(amount) AS REAL) / 100000000)) FROM txs WHERE epoch_period = $NEXTEPOCH")

        # Log Results
        expected_payment=$(awk -v qty=$qty_contracts -v amount=$payout_amount 'BEGIN {printf("%.8f\n", qty * amount / 100000000)}')
        ENTRY="$(date) - New Epoch (Number $NEXTEPOCH)!"$'\n'
        ENTRY="$ENTRY    Fee Results:"$'\n'
        ENTRY="$ENTRY        Total Fees: $TOTAL_FEES"$'\n'
        ENTRY="$ENTRY        TX Count: $TX_COUNT"$'\n'
        ENTRY="$ENTRY        Total Weight: $TOTAL_WEIGHT"$'\n'
        ENTRY="$ENTRY        Max Fee Rate: $MAXFEERATE"$'\n'
        ENTRY="$ENTRY    DB Query (payouts table)"$'\n'
        ENTRY="$ENTRY        $t_payout"$'\n'
        ENTRY="$ENTRY    UTXOs QTY: $qty_utxo"$'\n'
        ENTRY="$ENTRY    Expected Payment: $expected_payment"$'\n'
        ENTRY="$ENTRY    Total Payment: $total_payment"

        echo "$ENTRY" | sudo tee -a $LOG

        # Send Email
        fee_percent_diff=$(awk -v fee=$TOTAL_FEES -v payment=$total_payment 'BEGIN {printf("%.6f\n", ((fee / 100000000) / payment) * 100)}')
        bank_balance=$($BTC -rpcwallet=bank getbalance)
        send_email --epoch $NEXTEPOCH $TOTAL_FEES $TX_COUNT $TOTAL_WEIGHT $MAXFEERATE $qty_utxo $expected_payment $total_payment $fee_percent_diff $bank_balance "${t_payout//; /<br>}"

    else
        # Don't change text on next line! The string "next epoch" used for a conditional statement above.
        echo "$(date) - You have $(($BLOCKEPOCH - $($BTC getblockcount))) blocks to go for the next epoch (Number $NEXTEPOCH)" | sudo tee -a $LOG
    fi

elif [[ $1 = "-s" || $1 = "--send" ]]; then # Send the Money
    # See if error flag is present
    if [ -f /etc/send_payments_error_flag ]; then
        echo "$(date) - The \"--send\" payout routine was halted!" | sudo tee -a $LOG
        echo "    There was a serious error sending out payments last time." | sudo tee -a $LOG
        echo "    Hope you figured out why and was able to resolve it!" | sudo tee -a $LOG
        echo "    Remove file /etc/send_payments_error_flag for this routine to run again." | sudo tee -a $LOG
        exit 1
    fi

    # If there are no payments to process then just exit
    total_payment=$(sqlite3 $SQ3DBNAME "SELECT SUM(amount) FROM txs WHERE txid IS NULL")
    if [ -z $total_payment ]; then
        echo "$(date) - There are currently no payments to process." | sudo tee -a $LOG
        exit 0
    fi

    # Find out if there is enough money in the bank to execute payments
    bank_balance=$(awk -v balance=$($BTC -rpcwallet=bank getbalance) 'BEGIN {printf("%.0f\n", balance * 100000000)}')
    if [ $((total_payment + 100000000)) -gt $bank_balance ]; then
        message="$(date) - Not enough money in the bank to send payouts! The bank has $bank_balance $DENOMINATION, but it needs $((total_payment + 100000000)) $DENOMINATION before any payouts will be sent."
        echo $message | sudo tee -a $LOG
        send_email --info "Not Enough Money in The Bank" "$message"
    fi

    # Query db for tx_id, address, and amount - preparation to send out first set of payments
    tmp=$(sqlite3 $SQ3DBNAME "SELECT txs.tx_id, contracts.micro_address, txs.amount FROM contracts, txs WHERE contracts.contract_id = txs.contract_id AND txs.txid IS NULL LIMIT $TX_BATCH_SZ")
    eol=$'\n'; read -a query <<< ${tmp//$eol/ }
    total_sending=0
    start_time=$(date +%s)
    while [ ! -z "${tmp}" ]; do
        count=$(sqlite3 $SQ3DBNAME "SELECT COUNT(*) FROM txs WHERE txid IS NULL") # Get the total count of utxos to be generated
        echo "There are $count UTXOs left to be generated and submitted. (Batch Size: $TX_BATCH_SZ UTXOs/TX)"

        # Create individual arrays for each column (database insertion)
        read -a tmp <<< $(echo ${query[*]#*|})
        read -a ADDRESS <<< ${tmp[*]%|*}
        read -a AMOUNT <<< ${query[*]##*|}
        read -a TX_ID <<< ${query[*]%%|*}

        # Prepare outputs for the transactions
        utxos=""
        for ((i=0; i<${#TX_ID[@]}; i++)); do
            total_sending=$((total_sending + AMOUNT[i]))
            txo=$(awk -v amnt=${AMOUNT[i]} 'BEGIN {printf("%.8f\n", (amnt/100000000))}')
            utxos="$utxos\"${ADDRESS[i]}\":$txo,"
        done
        utxos=${utxos%?}

        # Make the transaction
        $UNLOCK
        TXID="" # Clear variable to further prove TXID uniqueness.
        TXID=$($BTC -rpcwallet=bank -named send outputs="{$utxos}" conf_target=10 estimate_mode="economical" | jq '.txid')
        if [[ ! ${TXID//\"/} =~ ^[0-9a-f]{64}$ ]]; then
            echo "$(date) - Serious Error!!! Invalid TXID: $TXID" | sudo tee -a $LOG
            send_email --info "Serious Error - Invalid TXID" "An invalid TXID was encountered while sending out payments"
            sudo touch /etc/send_payments_error_flag
            exit 1
        fi
        TX=$($BTC -rpcwallet=bank gettransaction ${TXID//\"/})

        # Update the DB with the TXID and vout
        for ((i=0; i<${#TX_ID[@]}; i++)); do
            sudo sqlite3 $SQ3DBNAME "UPDATE txs SET txid = $TXID, vout = $(echo $TX | jq .details[$i].vout) WHERE tx_id = ${TX_ID[i]};"
        done

        # Make sure the "count" of utxos to be generated is going down
        if [ $count -le $(sqlite3 $SQ3DBNAME "SELECT COUNT(*) FROM txs WHERE txid IS NULL") ]; then
            echo "$(date) - Serious Error!!! Infinite loop while sending out payments!" | sudo tee -a $LOG
            send_email --info "Serious Error - Sending Payments Indefinitely" "Infinite loop while sending out payments."
            sudo touch /etc/send_payments_error_flag
            exit 1
        fi

        # Query db for the next tx_id, address, and amount - preparation to officially send out payments for the next iteration of this loop.
        tmp=$(sqlite3 $SQ3DBNAME "SELECT txs.tx_id, contracts.micro_address, txs.amount FROM contracts, txs WHERE contracts.contract_id = txs.contract_id AND txs.txid IS NULL LIMIT $TX_BATCH_SZ")
        eol=$'\n'; read -a query <<< ${tmp//$eol/ }
    done
    end_time=$(date +%s)

    # Make sure all payments have been sent!
    if [ 0 -lt $(sqlite3 $SQ3DBNAME "SELECT COUNT(*) FROM txs WHERE txid IS NULL") ]; then
        echo "$(date) - Serious Error!!! Unfulfilled TXs in the DB after sending payments!" | sudo tee -a $LOG
        send_email --info "Serious Error - Unfulfilled TXs" "Unfulfilled TXs in the DB after sending payments."
        sudo touch /etc/send_payments_error_flag
        exit 1
    fi

    # Log Results
    post_bank_balance=$($BTC -rpcwallet=bank getbalance)
    bank_balance=$(awk -v num=$bank_balance 'BEGIN {printf("%.8f\n", num / 100000000)}')
    total_payment=$(awk -v num=$total_payment 'BEGIN {printf("%.8f\n", num / 100000000)}')
    total_sending=$(awk -v num=$total_sending 'BEGIN {printf("%.8f\n", num / 100000000)}')
    ENTRY="$(date) - All Payments have been completed successfully!"$'\n'
    ENTRY="$ENTRY    Execution Time: $((end_time - start_time)) seconds."$'\n'
    ENTRY="$ENTRY    Outputs Per TX: $TX_BATCH_SZ"$'\n'
    ENTRY="$ENTRY    Bank Balance: $bank_balance (Before Sending Payments)"$'\n'
    ENTRY="$ENTRY    Calculated Total: $total_payment"$'\n'
    ENTRY="$ENTRY    Total Sent: $total_sending"$'\n'
    ENTRY="$ENTRY    Bank Balance: $post_bank_balance (After Sending Payments)"
    echo "$ENTRY" | sudo tee -a $LOG

    # Send Email
    t_txids=$(sqlite3 -separator '; ' $SQ3DBNAME "SELECT DISTINCT txid FROM txs WHERE block_height IS NULL AND txid IS NOT NULL;")
    send_email --send $bank_balance $total_payment $total_sending $post_bank_balance $((end_time - start_time)) $TX_BATCH_SZ "$t_txids"

elif [[ $1 = "-c" || $1 = "--confirm" ]]; then # Confirm the sent payouts are confirmed in the blockchain; update the DB
    # Get all the txs that have a valid TXID without a block height
    tmp=$(sqlite3 $SQ3DBNAME "SELECT DISTINCT txid FROM txs WHERE block_height IS NULL AND txid IS NOT NULL;")
    eol=$'\n'; read -a query <<< ${tmp//$eol/ }

    if [ -z "${tmp}" ]; then
        echo "All transactions have been successfully confirmed on the blockchain."
        exit 0
    fi

    # See if each TXID has at least 6 confirmations; if so, update the block height in the DB.
    confirmed=0
    for ((i=0; i<${#query[@]}; i++)); do
        tmp=$($BTC -rpcwallet=bank gettransaction ${query[i]})

        CONFIRMATIONS=$(echo $tmp | jq '.confirmations')
        if [ $CONFIRMATIONS -ge "6" ]; then
            sudo sqlite3 $SQ3DBNAME "UPDATE txs SET block_height = $(echo $tmp | jq '.blockheight') WHERE txid = \"${query[i]}\";"
            confirmed=$((confirmed + 1))

            # Query DB
            echo "Confirmed:"; sqlite3 $SQ3DBNAME ".mode columns" "SELECT * FROM txs WHERE txid = \"${query[i]}\";"; echo ""
        else
            echo "NOT Confirmed! TXID \"${query[i]}\" has $CONFIRMATIONS confirmations (needs 6 or more)."; echo ""
        fi
    done

    # Log and Email
    if [ "$confirmed" = "0" ]; then # Simplify the log input (with no email) if there are no new confirmations.
        echo "$(date) - $((${#query[@]} - confirmed)) transaction(s) is/are still waiting to be confirmed on the blockchain with 6 or more confirmations." | sudo tee -a $LOG
    else
        echo "$(date) - ${confirmed} transaction(s) was/were confirmed on the blockchain with 6 or more confirmations." | sudo tee -a $LOG
        echo "    $((${#query[@]} - confirmed)) transaction(s) is/are still waiting to be confirmed on the blockchain with 6 or more confirmations." | sudo tee -a $LOG

        message="$(date) - ${confirmed} transaction(s) was/were confirmed on the blockchain with 6 or more confirmations.<br><br>"
        message="${message} $((${#query[@]} - confirmed)) transaction(s) is/are still waiting to be confirmed on the blockchain with 6 or more confirmations."

        send_email --info "Confirming Transaction(s) on The Blockchain" "$message"
    fi

elif [[  $1 = "-m" || $1 = "--email" ]]; then # Prepare all core customer notification emails for the latest epoch
    # Check to see if the latest epoch has already been "notified"
    notified=$(sqlite3 $SQ3DBNAME "SELECT notified FROM payouts WHERE epoch_period = (SELECT MAX(epoch_period) FROM payouts)")
    if [ ! -z $notified ]; then
        echo "No emails to prepare at this time!"
        exit 0
    fi

    # Generate payout data to be sent to each core customer
    tmp=$(sqlite3 $SQ3DBNAME << EOF
    SELECT
        accounts.account_id,
        (CASE WHEN accounts.preferred_name IS NULL THEN accounts.first_name ELSE accounts.preferred_name END),
        accounts.email,
        CAST(SUM(txs.amount) AS REAL) / 100000000,
        (SELECT CAST(SUM(amount) AS REAL) / 100000000
            FROM txs, contracts
            WHERE txs.contract_id = contracts.contract_id AND accounts.account_id = contracts.account_id),
        SUM(contracts.quantity) * $HASHESPERCONTRACT / 1000000000,
        (SELECT phone FROM accounts sub WHERE sub.account_id = accounts.contact),
        (SELECT email FROM accounts sub WHERE sub.account_id = accounts.contact)
    FROM accounts, txs, contracts
    WHERE accounts.account_id = contracts.account_id AND contracts.contract_id = txs.contract_id AND txs.epoch_period = (SELECT MAX(epoch_period) FROM payouts)
    GROUP BY accounts.account_id
EOF
    )
    eol=$'\n'; read -a tmp_notify_data <<< ${tmp//$eol/ }

    unset notify_data # Make sure the array is empty
    for ((i=0; i<${#tmp_notify_data[@]}; i++)); do
        notify_data[${tmp_notify_data[i]%%|*}]=${tmp_notify_data[i]#*|}
    done

    # Pivot all addresses associated with each account for this payout ('.' delimiter)
    tmp=$(sqlite3 $SQ3DBNAME << EOF
.separator "_"
    SELECT
        account_id,
        micro_address,
        active
    FROM contracts
    GROUP BY micro_address
EOF
    )
    eol=$'\n'; read -a tmp_addresses <<< ${tmp//$eol/ }

    unset addresses # Make sure the array is empty
    for ((i=0; i<${#tmp_addresses[@]}; i++)); do
        addresses[${tmp_addresses[i]%%_*}]=${addresses[${tmp_addresses[i]%%_*}]}.${tmp_addresses[i]#*_}
    done

    # Pivot all TXIDs ossociated with each account for this payout ('.' delimiter)
    tmp=$(sqlite3 $SQ3DBNAME << EOF
    SELECT
        contracts.account_id,
        txs.txid
    FROM txs, contracts
    WHERE txs.contract_id = contracts.contract_id AND txs.epoch_period = (SELECT MAX(epoch_period) FROM payouts)
    GROUP BY contracts.account_id, txs.txid
EOF
    )
    eol=$'\n'; read -a tmp_txids <<< ${tmp//$eol/ }

    unset txids # Make sure the array is empty
    for ((i=0; i<${#tmp_txids[@]}; i++)); do
        txids[${tmp_txids[i]%|*}]=${txids[${tmp_txids[i]%|*}]}.${tmp_txids[i]#*|}
    done

    # Format all the array data togethor
    for i in "${!notify_data[@]}"; do
        echo "./send_email.sh --payouts ${notify_data[$i]//|/ } \$SATRATE \$USDSATS ${addresses[$i]#*.} ${txids[$i]#*.}" | sudo tee -a /var/tmp/payout.emails
    done

    # Set the notified flag
    sudo sqlite3 $SQ3DBNAME "UPDATE payouts SET notified = 1 WHERE notified IS NULL;"

    # Log Results
    echo "$(date) - $(wc -l < /var/tmp/payout.emails) email(s) have been prepared to send to core customer(s)." | sudo tee -a $LOG

    # Send Email
    send_email --info "Core Customer Emails Are Ready to Send" "$(wc -l < /var/tmp/payout.emails) email(s) have been prepared to send to core customer(s)."

elif [[  $1 = "-d" || $1 = "--dump" ]]; then # Show all the contents of the database
    sqlite3 $SQ3DBNAME ".dump"

elif [[  $1 = "-a" || $1 = "--accounts" ]]; then # Show all accounts
    sqlite3 $SQ3DBNAME ".mode columns" "SELECT * FROM accounts"

elif [[  $1 = "-l" || $1 = "--sales" ]]; then # Show all sales
    sqlite3 $SQ3DBNAME ".mode columns" "SELECT sales.sale_id AS Sale, (accounts.first_name || ' ' || accounts.last_name) AS Name, sales.time AS Time, sales.quantity AS QTY, sales.status AS Status FROM accounts, sales WHERE accounts.account_id = sales.account_id"

elif [[  $1 = "-r" || $1 = "--contracts" ]]; then # Show all contracts
    sqlite3 $SQ3DBNAME ".mode columns" "SELECT * FROM contracts"

elif [[  $1 = "-x" || $1 = "--txs" ]]; then # Show all the transactions associated with the latest payout
    sqlite3 $SQ3DBNAME ".mode columns" "SELECT * FROM txs WHERE epoch_period = (SELECT MAX(epoch_period) FROM payouts);" # The latest transactions added to the DB

elif [[  $1 = "-p" || $1 = "--payouts" ]]; then # Show all payouts thus far
    sqlite3 $SQ3DBNAME ".mode columns" "SELECT * FROM payouts"

elif [[  $1 = "-t" || $1 = "--totals" ]]; then # Show total amounts for each contract (identical addresses are combinded)
    echo ""; echo ""; echo "Ordered by Account:"; echo "";
    sqlite3 $SQ3DBNAME << EOF
.mode columns
    SELECT (accounts.first_name || " " || accounts.last_name) AS Name,
        contracts.micro_address AS Addresses,
        CAST(SUM(txs.amount) as REAL) / 100000000 AS Totals
    FROM accounts, contracts, txs
    WHERE contracts.contract_id = txs.contract_id AND contracts.account_id = accounts.account_id
    GROUP BY contracts.micro_address
    ORDER BY accounts.account_id;
EOF

    echo ""; echo "Ordered by Contract ID:"; echo "";
    sqlite3 $SQ3DBNAME << EOF
.mode columns
    SELECT (accounts.first_name || " " || accounts.last_name) AS Name,
        contracts.micro_address AS Addresses,
        CAST(SUM(txs.amount) as REAL) / 100000000 AS Totals
    FROM accounts, contracts, txs
    WHERE contracts.contract_id = txs.contract_id AND contracts.account_id = accounts.account_id
    GROUP BY contracts.micro_address
    ORDER BY contracts.contract_id;
EOF


#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ Admin/Root Access Interface ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
elif [[  $1 = "--add-user" ]]; then # Add a new account
    CONTACT_EMAIL="${2,,}"; USER_EMAIL="${3,,}"; USER_PHONE="${4,,}"; FIRST_NAME="${5,,}"; LAST_NAME="${6,,}"; PREFERRED_NAME="${7,,}"; MASTER_EMAIL="${8,,}"

    # Very basic input checking
    if [[ -z $CONTACT_EMAIL || -z $USER_EMAIL || -z $USER_PHONE || -z $FIRST_NAME || -z $LAST_NAME || -z $PREFERRED_NAME || -z $MASTER_EMAIL ]]; then
        echo "Error! Insufficient Parameters!"
        exit 1
    elif [[ $CONTACT_EMAIL == "null" || $USER_EMAIL == "null"  || $FIRST_NAME == "null" ]]; then
        echo "Error! Contact email, user email, and first name are all required!"
        exit 1
    elif [[ $USER_PHONE == "null" && $MASTER_EMAIL == "null" ]]; then # Phone must be present if no "MASTER" is present
        echo "Error! No phone!"
        exit 1
    fi

    # Check for correct formats
    if [[ ! "$USER_EMAIL" =~ ^[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,4}$ ]]; then echo "Error! Invalid Email!"; exit 1; fi
    if [[ ! "$FIRST_NAME" =~ ^[a-z]+$ ]]; then echo "Error! Invalid First Name!"; exit 1; fi
    if [[ ! "$LAST_NAME" =~ ^[a-z]+$ ]]; then echo "Error! Invalid Last Name!"; exit 1; fi
    if [[ ! "$PREFERRED_NAME" =~ ^[a-z]+$ ]]; then echo "Error! Invalid Preferred Name!"; exit 1; fi
    if [[ "$USER_PHONE" != "null" && ! "$USER_PHONE" =~ ^[0-9]{3}-[0-9]{3}-[0-9]{4}$ ]]; then echo "Error! Invalid Phone Number (Format)!"; exit 1; fi

    # Make sure the "Master Email" is present if not null
    if [[ $MASTER_EMAIL != "null" ]]; then
        MASTER=$(sqlite3 $SQ3DBNAME "SELECT account_id FROM accounts WHERE email = '$MASTER_EMAIL'") # Get the account_id for the MASTER_EMAIL
        if [[ -z $MASTER ]]; then
            echo "Error! Master email is not in the DB!"
            exit 1
        fi
    else
        MASTER="NULL"
    fi

    # Make sure the "Contact Email" is present
    CONTACT=$(sqlite3 $SQ3DBNAME "SELECT account_id FROM accounts WHERE email = '$CONTACT_EMAIL'") # Get the account_id for the CONTACT_EMAIL
    if [[ -z $CONTACT ]]; then
        echo "Error! Contact email is not in the DB!"
        exit 1
    fi

    # Prepare variables that may contain the string "null" for the DB
    if [[ $USER_PHONE == "null" ]]; then USER_PHONE="NULL"; else USER_PHONE="'$USER_PHONE'"; fi
    if [[ $LAST_NAME == "null" ]]; then LAST_NAME="NULL"; else LAST_NAME="'${LAST_NAME^}'"; fi
    if [[ $PREFERRED_NAME == "null" ]]; then PREFERRED_NAME="NULL"; else PREFERRED_NAME="'${PREFERRED_NAME^}'"; fi

    # Insert into the DB
    sudo sqlite3 $SQ3DBNAME "INSERT INTO accounts (master, contact, first_name, last_name, preferred_name, email, phone, disabled) VALUES ($MASTER, $CONTACT, '${FIRST_NAME^}', $LAST_NAME, $PREFERRED_NAME, '$USER_EMAIL', $USER_PHONE, 0);"

    # Query the DB
    sqlite3 $SQ3DBNAME ".mode columns" "SELECT * FROM accounts WHERE email = '$USER_EMAIL'"

elif [[  $1 = "--disable-user" ]]; then # Disable an account (i.e. marks an account as disabled; it also disables all of the mining contracts pointing to this account)
    USER_EMAIL=$2
    exists=$(sqlite3 $SQ3DBNAME "SELECT EXISTS(SELECT * FROM accounts WHERE email = '${USER_EMAIL,,}')")
    if [[ $exists == "0" ]]; then
        echo "Error! Email does not exist in the database!"
        exit 1
    fi
    account_id=$(sqlite3 $SQ3DBNAME "SELECT account_id FROM accounts WHERE email = '${USER_EMAIL,,}'") # Get the account_id

    # Update the DB
    sudo sqlite3 $SQ3DBNAME "UPDATE accounts SET disabled = 1 WHERE email = '${USER_EMAIL,,}'"
    sudo sqlite3 $SQ3DBNAME "UPDATE contracts SET active = 0 WHERE account_id = $account_id"

    # Query the DB
    sqlite3 $SQ3DBNAME ".mode columns" "SELECT * FROM accounts WHERE email = '${USER_EMAIL,,}'"
    sqlite3 $SQ3DBNAME ".mode columns" "SELECT * FROM contracts WHERE account_id = $account_id"

elif [[  $1 = "--add-sale" ]]; then # Add a sale - Note: The User_Email is the one paying, but the resulting contracts can be assigned to anyone
    USER_EMAIL=$2; QTY=$3
    exists=$(sqlite3 $SQ3DBNAME "SELECT EXISTS(SELECT * FROM accounts WHERE email = '${USER_EMAIL,,}')")
    if [[ $exists == "0" ]]; then
        echo "Error! Email does not exist in the database!"
        exit 1
    fi
    if ! [[ $QTY =~ ^[0-9]+$ ]]; then
        echo "Error! Quantity is not a number!";
        exit 1
    fi
    account_id=$(sqlite3 $SQ3DBNAME "SELECT account_id FROM accounts WHERE email = '${USER_EMAIL,,}'") # Get the account_id

    # Insert into the DB
    sudo sqlite3 -bail $SQ3DBNAME << EOF
        PRAGMA foreign_keys = ON;
        INSERT INTO sales (account_id, time, quantity, status)
        VALUES ($account_id, $(date +%s), $QTY, 0);
EOF

    # Query the DB
    sqlite3 $SQ3DBNAME ".mode columns" "SELECT * FROM sales WHERE account_id = $account_id"
    echo ""; echo "Current Unix Time: $(date +%s)"

elif [[  $1 = "--update-sale" ]]; then # Update sale status - The "STATUS" can set to "PAID", "NOT_PAID", "TRIAL", or "DISABLED" ####################################
    SALE_ID=$2; STATUS=$3 ?????

# Add a contract
elif [[  $1 = "--add-contr" ]]; then
    USER_EMAIL=$2; SALE_ID=$3; QTY=$4; MICRO_ADDRESS=$5

# Mark a contract as delivered
elif [[  $1 = "--update-contr" ]]; then
    CONTRACT_ID=$2

# Disable a contract
elif [[  $1 = "--disable-contr" ]]; then
    CONTRACT_ID=$2








else
    echo "Method not found"
    echo "Run script with \"--help\" flag"
fi




#exchange rate = MATH.CIELING(100000000 / USD_PRICE), 2 decimal places)
#TZ=America/Phoenix date -d "$(date)" +%s
#TZ=America/Phoenix date -d @$UNIXTIMECODE
#date --date="30 hours ago" +%s
#date +%s
#
#
#/* Once an account has received a payout, it cannot be deleted and the account_id cannot be modified.
#If an account can be and is deleted, make sure all associated sales and contracts are also deleted.
#If an account is marked disabled, all of its associated sales must also be marked disabled.
#After the next payout, disabling cannot be reversed. */
#
#/* Make sure no tx happens that depends on a specific period before its reported epoch block time.
#Insert first row @ 0 manually 'cuz indexing starts at 1, but we need the period to start with 0
#Halvings occur in the middle of epoch periods; therefore, the subsidy for that epoch period that contains the halving will be an average.
#First halving occurs in epoch period 183 with an average of 11.25 coins/block - You should verify the math */
#
#/* Once a sale has received a payout, it cannot be deleted and some columns cannot be modified (sale_id, account_id, and quantity)
#If a sale can be and is deleted, make sure all associated contracts (and other contracts spawned from these contracts) are also deleted.
#If a sale is marked disabled, all of its associated contracts (and other contracts spawned from these contracts) must be marked inactive.
#After the next payout, disabling cannot be reversed. */
#
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#PRAGMA foreign_keys; /* See if it is turned on (1 for on) */
#PRAGMA foreign_keys = ON; /* Turn it on */
#.tables /* List all the tables in the database */
#DROP TABLE $TABLE; /* Deletes a table */
#
#INSERT INTO sales (account_id, date, quantity, unit_price)
#VALUES(5, 05022023, 500, 10000);
#
#DELETE FROM sales /* Delete a row */
#WHERE order_id = 2;
#
#sudo sqlite3 $SQ3DBNAME "INSERT INTO accounts (first_name, email) VALUES ($NAME, $EMAIL);" # Add new account
#sudo sqlite3 $SQ3DBNAME "INSERT INTO accounts (first_name, last_name, preferred_name, email) VALUES ($NAME, $EMAIL);" # Add new account
#
#sudo sqlite3 $SQ3DBNAME "INSERT INTO accounts (first_name, email) VALUES ($NAME, $EMAIL);" # Add new account
#
#
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ REMOVE ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#sudo sqlite3 $SQ3DBNAME "DELETE FROM payouts WHERE epoch_period = (SELECT MAX(epoch_period) FROM payouts);" # Remove last epoch_period from payouts
#sudo sqlite3 $SQ3DBNAME "DELETE FROM txs WHERE tx_id = (SELECT MAX(tx_id) FROM txs);" # Remove last tx from txs table
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ REPLACE/UPDATE ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#sudo sqlite3 $SQ3DBNAME "REPLACE INTO txs (tx_id, contract_id, epoch_period, txid, vout, amount, block_height, notes) VALUES (1078, 7, 87, 'b3845e7471af9db8eb04380dd5a811b4f2d1fbd6b5950834eff47c0ae66c1402', 1, 1423510430, 126174, NULL);"
#sudo sqlite3 $SQ3DBNAME "REPLACE INTO txs (tx_id, contract_id, epoch_period, txid, vout, amount, block_height, notes) VALUES (85, 7, 43, '635bc164350ff39afa8bf92a02b8242691f9393db5bb0f5f702a0057cd833134', 0, 1459059010, 62327, NULL);"


#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ QUERY ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#INSERT INTO accounts (email)
#VALUES("user@email.com");
#
#DELETE FROM accounts /* Delete a row */
#WHERE account_id = 8;

######### Set the SATRATE #########################
#    # Get btc/usd exchange rates from populat exchanges
#    BTCUSD=$(curl https://api.coinbase.com/v2/prices/BTC-USD/spot | jq '.data.amount') # Coinbase BTC/USD Price
#   #BTCUSD=$(curl "https://api.kraken.com/0/public/Ticker?pair=BTCUSD" | jq '.result.XXBTZUSD.a[0]') # Kraken BTC/USD Price
#    BTCUSD=${BTCUSD//\"/}
#    USDSATS=$(awk -v btcusd=$BTCUSD 'BEGIN {printf("%.3f\n", 100000000 / btcusd)}')

#    read -p "What is today's price (in $ATS) for ???????????????????????? : " SATRATE



# DEBUG/USEFULL COMMANDS ##################################
# echo $SQ3DBNAME

# sudo sqlite3 $SQ3DBNAME "UPDATE payouts SET satrate = 245 WHERE epoch_period = (SELECT MAX(epoch_period) FROM payouts);"

#echo "Hello World2" | sudo tee -a /var/tmp/payout.emails

#tail -n 1 /var/tmp/payout.emails
#sudo sed -i '$d' /var/tmp/payout.emails


#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ Administrative Checks ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#Send out emails to administrator-- Check. It kind of does that already
# Send out emails to Level 1 Hubs. What's that look like??
# Billing and keeping track of how much they have purchased.
# Got to figure this one out!
# Tellers Table and accounts




#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ Admin/Root Access Interface ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Add an account (USER_PHONE, PREFFERED_NAME, and MASTER_EMAIL is optional; however, USER_PHONE is highly reccommended if possible!)
#payouts --add-user CONTACT_EMAIL USER_EMAIL USER_PHONE FIRST_NAME LAST_NAME PREFFERED_NAME MASTER_EMAIL

# Disable an account (i.e. "deletes" an account, disables associated contracts, but retains its critical data)
#payouts --disable-user USER_EMAIL

# Add a sale - Note: This User is the one paying, but the resulting contracts can be assigned to anyone
#payouts --add-sale USER_EMAIL QTY

# Update sale status - The "STATUS" can set to "PAID", "NOT_PAID", "TRIAL", or "DISABLED"
#payouts --update-sale SALE_ID STATUS

# Add a contract
#payouts --add-contr USER_EMAIL SALE_ID QTY MICRO_ADDRESS

# Mark a contract as delivered
#payouts --update-contr CONTRACT_ID

# Disable a contract
#payouts --disable-contr CONTRACT_ID