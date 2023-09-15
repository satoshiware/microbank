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
      -s, --send        Send the Money
      -c, --confirm     Confirm the sent payouts are confirmed in the blockchain; updates the DB
      -m, --email-prep  Prepare all core customer notification emails for the latest epoch

----- Generic Database Queries ----------------------------------------------------------------------------------------------
      -d, --dump        Show all the contents of the database
      -a, --accounts    Show all accounts
      -l, --sales       Show all sales
      -r, --contracts   Show all contracts
      -x, --txs         Show all the transactions associated with the latest payout
      -p, --payouts     Show all payouts thus far
      -t, --totals      Show total amounts for each contract (identical addresses are combinded)

----- Admin/Root Interface --------------------------------------------------------------------------------------------------
      --add-user        Add a new account
            Parameters: CONTACT_EMAIL  USER_EMAIL  USER_PHONE**  FIRST_NAME  LAST_NAME*  PREFERRED_NAME*  MASTER_EMAIL*
                Note*: LAST_NAME, PREFERRED_NAME, and MASTER_EMAIL are options
                Note**: USER_PHONE is optional if MASTER_EMAIL was provided
      --disable-user    Disable an account (also disables associated contracts, but not the sales)
            Parameters: USER_EMAIL
      --add-sale        Add a sale
            Parameters: USER_EMAIL  QTY
                Note: The USER_EMAIL is the one paying, but the resulting contracts can be assigned to anyone (i.e. Sales don't have to match Contracts).
      --update-sale     Update sale status
            Parameters: USER_EMAIL  SALE_ID  STATUS
                Note: STATUS  =  0 (Not Paid),  1 (Paid),  2 (Trial Run),  3 (Disabled)
      --add-contr       Add a contract
            Parameters: USER_EMAIL  SALE_ID  QTY  MICRO_ADDRESS
      --update-contr    Mark every contract with this address as delivered
            Parameters: MICRO_ADDRESS
      --disable-contr   Disable a contract
            Parameters: MICRO_ADDRESS  CONTRACT_ID
                Note: Set CONTRACT_ID to "0" and all contracts matching MICRO_ADDRESS will be disabled

----- Email -----------------------------------------------------------------------------------------------------------------
      --send-teller-summary     Send summary to a Teller (Level 1) Hub/Node
            Parameters: EMAIL

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
        t_payout="${t_payout//; /<br>}"
        MESSAGE=$(cat << EOF
            <b><u>$(date) - New Epoch (Number $NEXTEPOCH)</u></b><br><br>

            <b>Fee Results:</b><br>
            <ul>
                <li><b>Total Fees:</b> $TOTAL_FEES</li>
                <li><b>TX Count:</b> $TX_COUNT</li>
                <li><b>Total Weight:</b> $TOTAL_WEIGHT</li>
                <li><b>Max Fee Rate:</b> $MAXFEERATE</li>
            </ul><br>

            <b>DB Query (payouts table)</b><br>
            $t_payout<br><br>

            <b>UTXOs QTY:</b> $qty_utxo<br>
            <b>Expected Payment:</b> $expected_payment<br>
            <b>Total Payment:</b> $total_payment<br><br>

            There was a <b>${fee_percent_diff} percent</b> effect upon the total payout from the tx fees collected.<br>
            Note: If this percent ever gets significantly and repeatedly large, there may be some bad players in the network gaming the system.<br><br>

            <b>Wallet (bank) Balance:</b> $bank_balance
EOF
        )
        send_email "Satoshi" "${ADMINISTRATOREMAIL}" "New Epoch Has Been Delivered" "$MESSAGE"

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
        send_email "Satoshi" "${ADMINISTRATOREMAIL}" "Not Enough Money in The Bank" "$message"
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
            send_email "Satoshi" "${ADMINISTRATOREMAIL}" "Serious Error - Invalid TXID" "An invalid TXID was encountered while sending out payments"
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
            send_email "Satoshi" "${ADMINISTRATOREMAIL}" "Serious Error - Sending Payments Indefinitely" "Infinite loop while sending out payments."
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
        send_email "Satoshi" "${ADMINISTRATOREMAIL}" "Serious Error - Unfulfilled TXs" "Unfulfilled TXs in the DB after sending payments."
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
    ENTRY="$ENTRY    Bank Balance: $post_bank_balance (After Sending Payments + TX Fees)"
    echo "$ENTRY" | sudo tee -a $LOG

    # Send Email
    t_txids=$(sqlite3 -separator '; ' $SQ3DBNAME "SELECT DISTINCT txid FROM txs WHERE block_height IS NULL AND txid IS NOT NULL;")
    time=$((end_time - start_time))
    MESSAGE=$(cat << EOF
        <b>$(date) - All Payments have been completed successfully</b><br>
        <ul>
            <li><b>Execution Time:</b> $time seconds</li>
            <li><b>Outputs Per TX:</b> $TX_BATCH_SZ</li>
            <li><b>Bank Balance:</b> $bank_balance (Before Sending Payments)</li>
            <li><b>Calculated Total:</b> $total_payment</li>
            <li><b>Total Sent:</b> $total_sending</li>
            <li><b>Bank Balance:</b> $post_bank_balance (After Sending Payments + TX Fees)</li>
        </ul><br>

        <b>DB Query (All Recent TXIDs)</b><br>
        $t_txids
EOF
    )
    send_email "Satoshi" "${ADMINISTRATOREMAIL}" "All Payments have been completed successfully" "$MESSAGE"

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
        echo "$(date) - ${#query[@]} transaction(s) is/are still waiting to be confirmed on the blockchain with 6 or more confirmations." | sudo tee -a $LOG
    else
        echo "$(date) - ${confirmed} transaction(s) was/were confirmed on the blockchain with 6 or more confirmations." | sudo tee -a $LOG
        echo "    $((${#query[@]} - confirmed)) transaction(s) is/are still waiting to be confirmed on the blockchain with 6 or more confirmations." | sudo tee -a $LOG

        message="$(date) - ${confirmed} transaction(s) was/were confirmed on the blockchain with 6 or more confirmations.<br><br>"
        message="${message} $((${#query[@]} - confirmed)) transaction(s) is/are still waiting to be confirmed on the blockchain with 6 or more confirmations."

        send_email "Satoshi" "${ADMINISTRATOREMAIL}" "Confirming Transaction(s) on The Blockchain" "$message"
    fi

elif [[  $1 = "-m" || $1 = "--email-prep" ]]; then # Prepare all core customer notification emails for the latest epoch
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
        echo "${notify_data[$i]//|/ } \$SATRATE \$USDSATS ${addresses[$i]#*.} ${txids[$i]#*.}" | sudo tee -a /var/tmp/payout.emails
    done

    # Set the notified flag
    sudo sqlite3 $SQ3DBNAME "UPDATE payouts SET notified = 1 WHERE notified IS NULL;"

    # Log Results
    echo "$(date) - $(wc -l < /var/tmp/payout.emails) email(s) have been prepared to send to core customer(s)." | sudo tee -a $LOG

    # Send Email
    send_email "Satoshi" "${ADMINISTRATOREMAIL}" "Core Customer Emails Are Ready to Send" "$(wc -l < /var/tmp/payout.emails) email(s) have been prepared to send to core customer(s)."

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ Generic Database Queries ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
elif [[  $1 = "-d" || $1 = "--dump" ]]; then # Show all the contents of the database
    sqlite3 $SQ3DBNAME ".dump"

elif [[  $1 = "-a" || $1 = "--accounts" ]]; then # Show all accounts
    sqlite3 $SQ3DBNAME ".mode columns" "SELECT * FROM accounts"

elif [[  $1 = "-l" || $1 = "--sales" ]]; then # Show all sales
    sqlite3 $SQ3DBNAME ".mode columns" "SELECT * FROM sales"
    echo ""; echo "Status: NOT_PAID = 0 or NULL; PAID = 1; TRIAL = 2; DISABLED = 3"
    echo ""; echo "Note: The contract owners and contract buyers don't have to match."
    echo "Example: Someone may buy extra contracts for a friend."; echo ""

elif [[  $1 = "-r" || $1 = "--contracts" ]]; then # Show all contracts
    sqlite3 $SQ3DBNAME ".mode columns" "SELECT * FROM contracts"

elif [[  $1 = "-x" || $1 = "--txs" ]]; then # Show all the transactions associated with the latest payout
    sqlite3 $SQ3DBNAME ".mode columns" "SELECT * FROM txs WHERE epoch_period = (SELECT MAX(epoch_period) FROM payouts);" # The latest transactions added to the DB

elif [[  $1 = "-p" || $1 = "--payouts" ]]; then # Show all payouts thus far
    sqlite3 $SQ3DBNAME ".mode columns" "SELECT * FROM payouts"

elif [[  $1 = "-t" || $1 = "--totals" ]]; then # Show total amounts for each contract (identical addresses are combinded)
    echo ""
    sqlite3 $SQ3DBNAME << EOF
.mode columns
    SELECT
        accounts.first_name || COALESCE(' (' || accounts.preferred_name || ') ', ' ') || COALESCE(accounts.last_name, '') AS Name,
        contracts.micro_address AS Address,
        CAST(SUM(txs.amount) as REAL) / 100000000 AS Total
    FROM accounts, contracts, txs
    WHERE contracts.contract_id = txs.contract_id AND contracts.account_id = accounts.account_id
    GROUP BY contracts.micro_address
    ORDER BY accounts.account_id;
EOF
    echo ""

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ Admin/Root Interface ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
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
    if [[ ! "$LAST_NAME" =~ ^[a-z-]+$ ]]; then echo "Error! Invalid Last Name!"; exit 1; fi
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
    sudo sqlite3 $SQ3DBNAME << EOF
        PRAGMA foreign_keys = ON;
        INSERT INTO sales (account_id, time, quantity, status)
        VALUES ($account_id, $(date +%s), $QTY, 0);
EOF

    # Query the DB
    sqlite3 $SQ3DBNAME ".mode columns" "SELECT * FROM sales WHERE account_id = $account_id"
    SALE_ID=$(sqlite3 $SQ3DBNAME "SELECT sale_id FROM sales WHERE account_id = $account_id ORDER BY sale_id DESC LIMIT 1")
    echo ""; echo "Current Unix Time: $(date +%s)"
    echo "Your new \"Sale ID\": $SALE_ID"; echo ""

elif [[  $1 = "--update-sale" ]]; then # Update sale status
    USER_EMAIL=$2; SALE_ID=$3; STATUS=$4

    if ! [[ $SALE_ID =~ ^[0-9]+$ ]]; then echo "Error! \"Sale ID\" is not a number!"; exit 1; fi
    exists=$(sqlite3 $SQ3DBNAME "SELECT EXISTS(SELECT * FROM sales WHERE account_id = (SELECT account_id FROM accounts WHERE email = '${USER_EMAIL,,}') AND sale_id = $SALE_ID)")
    if [[ $exists == "0" ]]; then
        echo "Error! \"User Email\" with provided \"Sale ID\" does not exist in the database!"
        exit 1
    fi

    if ! [[ $STATUS =~ ^[0-9]+$ ]]; then
        echo "Error! Status code is not a number!";
        exit 1
    elif [[ $STATUS == "0" ]]; then echo "Update to \"Not Paid\""
    elif [[ $STATUS == "1" ]]; then echo "Update to \"Paid\""
    elif [[ $STATUS == "2" ]]; then echo "Update to \"Trial Run\""
    elif [[ $STATUS == "3" ]]; then echo "Update to \"Disabled\""; else
        echo "Error! Invalid status code!";
        exit 1
    fi

    # Update the DB
    sudo sqlite3 $SQ3DBNAME "UPDATE sales SET status = $STATUS WHERE sale_id = $SALE_ID"
    if [[ $STATUS == "3" ]]; then
        sudo sqlite3 $SQ3DBNAME "UPDATE contracts SET active = 0 WHERE sale_id = $SALE_ID"
    fi

    # Query the DB
    echo ""; sqlite3 $SQ3DBNAME ".mode columns" "SELECT * FROM sales WHERE sale_id = $SALE_ID"; echo ""
    if [[ $STATUS == "3" ]]; then
        sqlite3 $SQ3DBNAME ".mode columns" "SELECT * FROM contracts WHERE sale_id = $SALE_ID"; echo ""
    fi

elif [[  $1 = "--add-contr" ]]; then # Add a contract
    USER_EMAIL=$2; SALE_ID=$3; QTY=$4; MICRO_ADDRESS=$5

    if ! [[ $SALE_ID =~ ^[0-9]+$ ]]; then echo "Error! \"Sale ID\" is not a number!"; exit 1; fi
    exists=$(sqlite3 $SQ3DBNAME "SELECT EXISTS(SELECT * FROM sales WHERE sale_id = $SALE_ID)")
    if [[ $exists == "0" ]]; then
        echo "Error! \"Sale ID\" does not exist in the database!"
        exit 1
    fi

    exists=$(sqlite3 $SQ3DBNAME "SELECT EXISTS(SELECT * FROM accounts WHERE email = '${USER_EMAIL,,}')")
    if [[ $exists == "0" ]]; then
        echo "Error! \"User Email\" does not exist in the database!"
        exit 1
    fi

    if ! [[ $QTY =~ ^[0-9]+$ ]]; then
        echo "Error! Quantity provided is not a number!"
        exit 1
    elif [[ $QTY == "0" ]]; then
        echo "Error! Quantity provided is zero!"
        exit 1
    fi
    total=$(sqlite3 $SQ3DBNAME "SELECT quantity FROM sales WHERE sale_id = $SALE_ID")
    assigned=$(sqlite3 $SQ3DBNAME "SELECT SUM(quantity) FROM contracts WHERE sale_id = $SALE_ID" AND active != 0)
    if [[ ! $QTY -le $((total - assigned)) ]]; then
        echo "Error! The \"Sale ID\" provided cannot accommodate more than $((total - assigned)) \"shares\"!"
        exit 1
    fi

    if ! [[ $($BTC validateaddress ${MICRO_ADDRESS,,} | jq '.isvalid') == "true" ]]; then
        echo "Error! Address provided is not correct or Bitcoin Core (microcurrency mode) is down!"
        exit 1
    fi

    # Insert into the DB
    ACCOUNT_ID=$(sqlite3 $SQ3DBNAME "SELECT account_id FROM accounts WHERE email = '${USER_EMAIL,,}'")
    sudo sqlite3 $SQ3DBNAME << EOF
        PRAGMA foreign_keys = ON;
        INSERT INTO contracts (account_id, sale_id, quantity, time, active, delivered, micro_address)
        VALUES ($ACCOUNT_ID, $SALE_ID, $QTY, $(date +%s), 1, 0, '${MICRO_ADDRESS,,}');
EOF

    # If there is a preexisting contract with the same address that is marked "delivered" then mark this delivered!
    exists=$(sqlite3 $SQ3DBNAME "SELECT EXISTS(SELECT * FROM contracts WHERE micro_address = '${MICRO_ADDRESS,,}' AND delivered = 1)")
    if [[ $exists == "1" ]]; then
        $0 --deliver-contr $MICRO_ADDRESS > /dev/null
    fi

    # Query the DB
    sqlite3 $SQ3DBNAME ".mode columns" "SELECT * FROM contracts WHERE account_id = $ACCOUNT_ID"

elif [[  $1 = "--deliver-contr" ]]; then # Mark a contract as delivered
    MICRO_ADDRESS=$2

    exists=$(sqlite3 $SQ3DBNAME "SELECT EXISTS(SELECT * FROM contracts WHERE micro_address = '${MICRO_ADDRESS,,}')")
    if [[ $exists == "0" ]]; then
        echo "Error! The \"Microcurrency Address\" provided does not exist in the database!"
        exit 1
    fi

    # Update the DB
    sudo sqlite3 $SQ3DBNAME "UPDATE contracts SET delivered = 1 WHERE micro_address = '${MICRO_ADDRESS,,}'"

    # Query the DB
    sqlite3 $SQ3DBNAME ".mode columns" "SELECT * FROM contracts WHERE micro_address = '${MICRO_ADDRESS,,}'"

elif [[  $1 = "--disable-contr" ]]; then # Disable a contract
    MICRO_ADDRESS=$2; CONTRACT_ID=$3

    if ! [[ $CONTRACT_ID =~ ^[0-9]+$ ]]; then echo "Error! \"Contract ID\" is not a number!"; exit 1; fi
    if [[ $CONTRACT_ID == "0" ]]; then
        exists=$(sqlite3 $SQ3DBNAME "SELECT EXISTS(SELECT * FROM contracts WHERE micro_address = '${MICRO_ADDRESS,,}')")
        if [[ $exists == "0" ]]; then
            echo "Error! The \"Microcurrency Address\" provided does not exist in the database!"
            exit 1
        fi
    else
        exists=$(sqlite3 $SQ3DBNAME "SELECT EXISTS(SELECT * FROM contracts WHERE micro_address = '${MICRO_ADDRESS,,}' AND contract_id = $CONTRACT_ID)")
        if [[ $exists == "0" ]]; then
            echo "Error! \"Microcurrency Address\" with provided \"Contract ID\" does not exist in the database!"
            exit 1
        fi
    fi

    # Update the DB
    if [[ $CONTRACT_ID == "0" ]]; then
        sudo sqlite3 $SQ3DBNAME "UPDATE contracts SET active = 0 WHERE micro_address = '${MICRO_ADDRESS,,}'"
    else
        sudo sqlite3 $SQ3DBNAME "UPDATE contracts SET active = 0 WHERE micro_address = '${MICRO_ADDRESS,,}' AND contract_id = $CONTRACT_ID"
    fi

    # Query the DB
    sqlite3 $SQ3DBNAME ".mode columns" "SELECT * FROM contracts WHERE micro_address = '${MICRO_ADDRESS,,}'"

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ Emails ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
elif [[  $1 = "--send-teller-summary" ]]; then # Send summary to a Teller (Level 1) Hub/Node
    CONTACT_EMAIL=$2

    NAME=$(sqlite3 $SQ3DBNAME << EOF
        SELECT
            CASE WHEN preferred_name IS NULL
                THEN first_name
                ELSE preferred_name
            END
        FROM accounts
        WHERE email = '${CONTACT_EMAIL,,}'
EOF
    )

    MESSAGE="Hi $NAME<br><br> Here are all your contract details!<br><br><hr>"

    # Accounts
    MESSAGE="$MESSAGE<br><br><b>Accounts:</b><br><table border="1"><tr><th>Name</th><th>Master</th><th>Email</th><th>Phone</th><th>Total Received</th></tr>"
    MESSAGE="$MESSAGE"$(sqlite3 $SQ3DBNAME << EOF
.separator ''
        SELECT
            '<tr>',
            '<td>' || first_name || COALESCE(' (' || preferred_name || ') ', ' ') || COALESCE(last_name, '') || '</td>',
            '<td>' || COALESCE((SELECT first_name || COALESCE(' (' || preferred_name || ') ', ' ') || COALESCE(last_name, '') FROM accounts _accounts WHERE account_id = accounts.master), '') || '</td>',
            '<td>' || email || '</td>',
            '<td>' || COALESCE(phone, '') || '</td>',
            '<td>' || (SELECT CAST(SUM(amount) AS REAL) / 100000000 FROM txs, contracts WHERE txs.contract_id = contracts.contract_id AND accounts.account_id = contracts.account_id) || '</td>',
            '</tr>'
        FROM accounts
        WHERE contact = (SELECT account_id FROM accounts WHERE email = '${CONTACT_EMAIL,,}') AND disabled = 0
EOF
    );  MESSAGE="$MESSAGE</table>"

    # Sales/Contracts
    MESSAGE="$MESSAGE<br><br><b>Sales/Contracts:</b><br><table border="1"><tr><th>Name</th><th>QTY/Total</th><th>Sale ID</th><th>Purchaser</th><th>Time</th><th>Address</th><th>Total Received</th></tr>"
    MESSAGE="$MESSAGE"$(sqlite3 $SQ3DBNAME << EOF
.separator ''
        SELECT
            '<tr>',
            '<td>' || (SELECT first_name || COALESCE(' (' || preferred_name || ') ', ' ') || COALESCE(last_name, '') FROM accounts WHERE account_id = contracts.account_id) || '</td>',
            '<td>' || quantity || '/' || (SELECT quantity FROM sales WHERE sale_id = contracts.sale_id) || '</td>',
            '<td>' || sale_id || '</td>',
            '<td>' || (SELECT first_name || COALESCE(' (' || preferred_name || ') ', ' ') || COALESCE(last_name, '') FROM accounts WHERE account_id = (SELECT account_id FROM sales WHERE sale_id = contracts.sale_id)) || '</td>',
            '<td>' || DATETIME(time, 'unixepoch', 'localtime') || '</td>',
            '<td>' || micro_address || IIF(active = 2, ' (Opened)', '') || '</td>',
            '<td>' || (SELECT CAST(SUM(txs.amount) as REAL) / 100000000 FROM txs WHERE contract_id = contracts.contract_id) || '</td>',
            '</tr>'
        FROM contracts
        WHERE active = 1 AND (SELECT contact FROM accounts WHERE account_id = contracts.account_id) = (SELECT account_id FROM accounts WHERE email = '${CONTACT_EMAIL,,}')
EOF
);  MESSAGE="$MESSAGE</table>"

    # Not Delivered
    MESSAGE="$MESSAGE<br><br><b>Not Delivered:</b><br><table border="1"><tr><th>Name</th><th>Email</th><th>Contract ID</th><th>QTY</th><th>Time</th><th>Addresses</th></tr>"
    MESSAGE="$MESSAGE"$(sqlite3 $SQ3DBNAME << EOF
.separator ''
        SELECT
            '<tr>',
            '<td>' || (SELECT first_name || COALESCE(' (' || preferred_name || ') ', ' ') || COALESCE(last_name, '') FROM accounts WHERE account_id = contracts.account_id) || '</td>',
            '<td>' || (SELECT email FROM accounts WHERE account_id = contracts.account_id) || '</td>',
            '<td>' || contract_id || '</td>',
            '<td>' || quantity || '</td>',
            '<td>' || DATETIME(time, 'unixepoch', 'localtime') || '</td>',
            '<td>' || micro_address || '</td>',
            '</tr>'
        FROM contracts
        WHERE delivered = 0 AND (SELECT contact FROM accounts WHERE account_id = contracts.account_id) = (SELECT account_id FROM accounts WHERE email = '${CONTACT_EMAIL,,}')
        GROUP BY micro_address
EOF
    );  MESSAGE="$MESSAGE</table>"

    #Underutilized
    MESSAGE="$MESSAGE<br><br><b>Underutilized:</b><br><table border="1"><tr><th>Purchaser</th><th>Email</th><th>Sale ID</th><th>QTY/Total</th><th>Remaining</th><th>Time</th></tr>"
    MESSAGE="$MESSAGE"$(sqlite3 $SQ3DBNAME << EOF
.separator ''
        SELECT
            '<tr>',
            '<td>' || (SELECT first_name || COALESCE(' (' || preferred_name || ') ', ' ') || COALESCE(last_name, '') FROM accounts WHERE account_id = sales.account_id) || '</td>',
            '<td>' || (SELECT email FROM accounts WHERE account_id = sales.account_id) || '</td>',
            '<td>' || sale_id || '</td>',
            '<td>' || (SELECT SUM(quantity) FROM contracts WHERE sale_id = sales.sale_id AND active != 0) || '\' || quantity || '</td>',
            '<td>' || quantity - (SELECT SUM(quantity) FROM contracts WHERE sale_id = sales.sale_id AND active != 0) || '</td>',
            '<td>' || DATETIME(sales.time, 'unixepoch', 'localtime') || '</td>',
            '</tr>'
        FROM sales
        WHERE status != 3 AND (SELECT contact FROM accounts WHERE account_id = sales.account_id) = (SELECT account_id FROM accounts WHERE email = '${CONTACT_EMAIL,,}')
            AND (quantity - (SELECT SUM(quantity) FROM contracts WHERE sale_id = sales.sale_id AND active != 0)) > 0
EOF
    );  MESSAGE="$MESSAGE</table>"

    # Not Paid
    MESSAGE="$MESSAGE<br><br><b>Not Paid:</b><br><table border="1"><tr><th>Name</th><th>Email</th><th>Sale ID</th><th>Total</th><th>Time</th></tr>"
    MESSAGE="$MESSAGE"$(sqlite3 $SQ3DBNAME << EOF
.separator ''
        SELECT
            '<tr>',
            '<td>' || (SELECT first_name || COALESCE(' (' || preferred_name || ') ', ' ') || COALESCE(last_name, '') FROM accounts WHERE account_id = sales.account_id) || '</td>',
            '<td>' || (SELECT email FROM accounts WHERE account_id = sales.account_id) || '</td>',
            '<td>' || sale_id || '</td>',
            '<td>' || quantity || '</td>',
            '<td>' || DATETIME(time, 'unixepoch', 'localtime') || '</td>',
            '</tr>'
        FROM sales
        WHERE status = 0 AND (SELECT contact FROM accounts WHERE account_id = sales.account_id) = (SELECT account_id FROM accounts WHERE email = '${CONTACT_EMAIL,,}')
EOF
    );  MESSAGE="$MESSAGE</table>"

    # Trials
    MESSAGE="$MESSAGE<br><br><b>Trials:</b><br><table border="1"><tr><th>Name</th><th>Email</th><th>Sale ID</th><th>Total</th><th>Time</th><th>Days Active</th></tr>"
    MESSAGE="$MESSAGE"$(sqlite3 $SQ3DBNAME << EOF
.separator ''
        SELECT
            '<tr>',
            '<td>' || (SELECT first_name || COALESCE(' (' || preferred_name || ') ', ' ') || COALESCE(last_name, '') FROM accounts WHERE account_id = sales.account_id) || '</td>',
            '<td>' || (SELECT email FROM accounts WHERE account_id = sales.account_id) || '</td>',
            '<td>' || sale_id || '</td>',
            '<td>' || quantity || '</td>',
            '<td>' || DATETIME(time, 'unixepoch', 'localtime') || '</td>',
            '<td>' || ((STRFTIME('%s') - time) / 86400) || '</td>',
            '</tr>'
        FROM sales
        WHERE status = 2 AND (SELECT contact FROM accounts WHERE account_id = sales.account_id) = (SELECT account_id FROM accounts WHERE email = '${CONTACT_EMAIL,,}')
EOF
    );  MESSAGE="$MESSAGE</table>"

    send_email "$NAME" "${CONTACT_EMAIL,,}" "Teller (Lvl 1) Contract Summary" "$MESSAGE"

else
    echo "Method not found"
    echo "Run script with \"--help\" flag"
fi

##################################
#SQ3DBNAME=/var/lib/btcofaz.db
#LOG=/var/log/payout.log
# echo $SQ3DBNAME
#    # Get btc/usd exchange rates from populat exchanges
#    BTCUSD=$(curl https://api.coinbase.com/v2/prices/BTC-USD/spot | jq '.data.amount') # Coinbase BTC/USD Price
#   #BTCUSD=$(curl "https://api.kraken.com/0/public/Ticker?pair=BTCUSD" | jq '.result.XXBTZUSD.a[0]') # Kraken BTC/USD Price
#    BTCUSD=${BTCUSD//\"/}
#    USDSATS=$(awk -v btcusd=$BTCUSD 'BEGIN {printf("%.3f\n", 100000000 / btcusd)}')

#    read -p "What is today's price (in $ATS) for ???????????????????????? : " SATRATE
# sudo sqlite3 $SQ3DBNAME "UPDATE payouts SET satrate = 245 WHERE epoch_period = (SELECT MAX(epoch_period) FROM payouts);"
#tail -n 1 /var/tmp/payout.emails
#sudo sed -i '$d' /var/tmp/payout.emails

##################### What's the next thing most critical #######################################
#1) Make it easier to sendout those emails.
#3) Upgrate db to accomidate Level 1 more professionally. You know, payout those extra hashes!!!
#4) Write a routine that sees if any of the addresses have been opened and mark the DB accordinally.
#5) Payout number on the payout
#6) Product Master Emails

#payouts --add-contr Ch@ymail.com 46 5 az1q3q....2p7
#Error: near "AND": syntax error