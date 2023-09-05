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
EOF

    echo "Assign static values to all the variables in the \"/etc/default/_payouts.env\" file"
    echo "Rename file to \"payouts.env\" (from \"_payouts.env\") when finished"
    exit 0
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
    echo ""; echo "log file is located at \"~/payout.log\""
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
      -d, --dump        Show all the contents of the database
      -a, --accounts    Show all accounts
      -l, --sales       Show all sales
      -r, --contracts   Show all contracts
      -x, --txs         Show all the transactions associated with the latest payout
      -p, --payouts     Show all payouts thus far
      -t, --totals      Show total amounts for each contract (identical addresses are combinded)
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
		
		
		NEXTEPOCH=105
		pout=$(sqlite3 -separator '; ' $SQ3DBNAME "SELECT 'Epoch Period: ' || epoch_period, 'Block Start: ' || block_height, 'Subsidy: ' || subsidy, 'Fees: ' || total_fees, 'Time: ' || block_time, 'Difficulty: ' || difficulty, 'Payout: ' || amount FROM payouts WHERE epoch_period = $NEXTEPOCH")
		conqty=$(sqlite3 $SQ3DBNAME "SELECT COUNT(*) FROM txs WHERE epoch_period = $NEXTEPOCH")
		totalpayoutamount=$(sqlite3 $SQ3DBNAME "SELECT SUM(amount) FROM txs WHERE epoch_period = $NEXTEPOCH")
		
		
		# Total amount of payouts... Was it a success??? What is the total expected?
		sqlite3 $SQ3DBNAME "SELECT contract_id, quantity FROM contracts WHERE active != 0 AND time<=$BLOCKTIME"
		
		
	 
    
    
    
    
        




		
		
		# Log Results
		echo "$(date) - Fee calculation complete for next epoch (Number $NEXTEPOCH) - TOTAL_FEES: $TOTAL_FEES, TX_COUNT: $TX_COUNT, TOTAL_WEIGHT: $TOTAL_WEIGHT, MAXFEERATE: $MAXFEERATE" | sudo tee -a $LOG
		
		# Send Email
    else
        # Don't change text on next line! The string "next epoch" used for a conditional statement above.
        echo "$(date) - You have $(($BLOCKEPOCH - $($BTC getblockcount))) blocks to go for the next epoch (Number $NEXTEPOCH)" | sudo tee -a $LOG
    fi

####### How much did the TOTALFEES have on the payout???? Should we divide it? when we report it? yes ############   just compare it with the total subsidy 1440 * subisidy and represent it as a percent. 
##### Give some information to the user here. they will be interested to know....


# TODO LIST ##################################
# The fee rate on the transaction is fixed. What can we do to make it dynamic
# EMAIL and update LOG after routine

# Send routine
#### Check if there is enough money, before sending (LOG and email on error)
#### Verify TXID, Print TXID to the LOG File (ALL PASS THROUGHS), EXIT if TXID was not good and verify balance did not change if so, bigger SECOND WORST CASE!!!!.
#### If all went well, and there is still more txs to make then recursivly call routine. Other wise, EMAIL and LOG.
#### Check for worst case. TXID is valid, but the DB was not updated correctly: Fill in all TXID that null with error, LOG, EMAIL

# Confirm routine. reread the newly updated database. Update LOG and EMAIL.

# DEBUG/USEFULL COMMANDS ##################################
# sudo sqlite3 $SQ3DBNAME "DELETE FROM payouts WHERE epoch_period = (SELECT MAX(epoch_period) FROM payouts);"
# sudo sqlite3 $SQ3DBNAME "UPDATE payouts SET satrate = 245 WHERE epoch_period = (SELECT MAX(epoch_period) FROM payouts);"
# sudo sqlite3 $SQ3DBNAME "UPDATE payouts SET notified = 1 WHERE notified IS NULL;"










elif [[ $1 = "-s" || $1 = "--send" ]]; then # Send the Money
    if [ -z "${2}" ]; then # Check for second parameter (if it does not exist)
        QTYOUTS=1
    else
        re='^[0-9]+$'
        if ! [[ ${2} =~ $re ]]; then # Make sure second parameter is a number
            echo "Error! \"${2}\" is not an integer!"
            exit 1
        fi
        QTYOUTS="${2}"
    fi

    # Query db for tx_id, address, and amount - preparation to officially send out payments
    tmp=$(sqlite3 $SQ3DBNAME "SELECT txs.tx_id, contracts.micro_address, txs.amount FROM contracts, txs WHERE contracts.contract_id = txs.contract_id AND txs.txid is NULL LIMIT $QTYOUTS")
    eol=$'\n'; read -a query <<< ${tmp//$eol/ }

    # If there are no more transaction to process then just exit.
    if [ -z "${tmp}" ]; then
        echo "All payout transactions have been fullfilled."
        exit 0
    fi

    # Create individual arrays for each column
    read -a tmp <<< $(echo ${query[*]#*|})
    read -a ADDRESS <<< ${tmp[*]%|*}
    read -a AMOUNT <<< ${query[*]##*|}
    read -a TX_ID <<< ${query[*]%%|*}

    # Prepare outputs for the transactions
    utxos=""
    for ((i=0; i<${#TX_ID[@]}; i++)); do
        txo=$(awk -v amnt=${AMOUNT[i]} 'BEGIN {printf("%.8f\n", (amnt/100000000))}')
        utxos="$utxos\"${ADDRESS[i]}\":$txo,"
    done
    utxos=${utxos%?}

    # Make the transaction
    $UNLOCK
    TXID=$($BTC -rpcwallet=bank -named send outputs="{$utxos}" fee_rate=1 | jq '.txid')
    TX=$($BTC -rpcwallet=bank gettransaction ${TXID//\"/})

    # Update the DB with the TXID and vout
    for ((i=0; i<${#TX_ID[@]}; i++)); do
        sudo sqlite3 $SQ3DBNAME "UPDATE txs SET txid = $TXID, vout = $(echo $TX | jq .details[$i].vout) WHERE tx_id = ${TX_ID[i]};"
    done

    # Query DB
    echo ""; sqlite3 $SQ3DBNAME ".mode columns" "SELECT * FROM txs WHERE txid = $TXID"; echo ""

    # Run this routine resursively in case there are more
    echo "Press enter to send again!"; read VAR
    $0 $1 $2

elif [[ $1 = "-c" || $1 = "--confirm" ]]; then # Confirm the sent payouts are confirmed in the blockchain; update the DB
    # Get all the txs that have a valid TXID without a block height
    tmp=$(sqlite3 $SQ3DBNAME "SELECT DISTINCT txid FROM txs WHERE block_height IS NULL AND txid IS NOT NULL;")
    eol=$'\n'; read -a query <<< ${tmp//$eol/ }

    if [ -z "${tmp}" ]; then
        echo "All transactions have been successfully confirmed on the blockchain."
        exit 0
    fi

    # See if each TXID has at least 6 confirmations; if so, update the block height in the DB.
    for ((i=0; i<${#query[@]}; i++)); do
        tmp=$($BTC -rpcwallet=bank gettransaction ${query[i]})

        CONFIRMATIONS=$(echo $tmp | jq '.confirmations')
        if [ $CONFIRMATIONS -ge "6" ]; then
            sudo sqlite3 $SQ3DBNAME "UPDATE txs SET block_height = $(echo $tmp | jq '.blockheight') WHERE txid = \"${query[i]}\";"

            # Query DB
            echo "Confirmed:"; sqlite3 $SQ3DBNAME ".mode columns" "SELECT * FROM txs WHERE txid = \"${query[i]}\";"; echo ""
        else
            echo "NOT Confirmed! TXID \"${query[i]}\" has $CONFIRMATIONS confirmations (needs 6 or more)."; echo ""
        fi
    done

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

elif [[  $1 = "-m" || $1 = "--email" ]]; then # Show all payouts thus far  (a 2nd parameter will limit the NUMBER of rows displayed - in descending order)
    # Get btc/usd exchange rates from populat exchanges
    BTCUSD=$(curl https://api.coinbase.com/v2/prices/BTC-USD/spot | jq '.data.amount') # Coinbase BTC/USD Price
    #BTCUSD=$(curl "https://api.kraken.com/0/public/Ticker?pair=BTCUSD" | jq '.result.XXBTZUSD.a[0]') # Kraken BTC/USD Price
    BTCUSD=${BTCUSD//\"/}
    USDSATS=$(awk -v btcusd=$BTCUSD 'BEGIN {printf("%.3f\n", 100000000 / btcusd)}')

    read -p "What is today's price (in $ATS) for ???????????????????????? : " SATRATE

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

    # Format all the array data togethor <<<<<<<<<<<<<<<<<<<<<<<<<<< WE ARE HERE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    for i in "${!notify_data[@]}"; do
        echo "./send_email.sh ${notify_data[$i]//|/ } $SATRATE $USDSATS ${addresses[$i]#*.} ${txids[$i]#*.}"
    done

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
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ QUERY ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#sqlite3 $SQ3DBNAME ".dump" # Show all the contents of the database
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#sqlite3 $SQ3DBNAME << EOF # Show all payout information
#.mode columns
#SELECT * FROM payouts
#EOF
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#EPOCHTIME=10000000000 # Show all "active" contract information (w\ timestamp before or equal to the desired payout epoch)
#sqlite3 $SQ3DBNAME << EOF
#.mode columns
#SELECT * FROM contracts WHERE active=1 AND time<=$EPOCHTIME
#EOF
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#sqlite3 $SQ3DBNAME "SELECT * FROM txs WHERE amount = (SELECT MAX(amount) FROM txs);" # Get the TX with the biggest amount
#sqlite3 $SQ3DBNAME "SELECT * FROM txs WHERE amount = (SELECT MIN(amount) FROM txs);" # Get the TX with the smallest amount
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#
#sqlite3 $SQ3DBNAME .mode columns
#sqlite3 $SQ3DBNAME "SELECT * FROM accounts" # View all accounts
#sqlite3 $SQ3DBNAME "SELECT account_id, association, master, contact, first_name, last_name, preferred_name, email, email_frequency, phone, phone_frequency, disable, address, notes FROM accounts"
#
#
#
#SELECT DISTINCT column_list
#FROM table_list
#  JOIN table ON join_condition
#WHERE row_filter
#ORDER BY column
#LIMIT count OFFSET offset
#GROUP BY column
#HAVING group_filter;
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#INSERT INTO accounts (email)
#VALUES("user@email.com");
#
#DELETE FROM accounts /* Delete a row */
#WHERE account_id = 8;


#echo "txids" > ~/report.txt
#btc -rpcwallet=bank -named send outputs='{"ut1qnsfzalxfn2d3ml648mnuk6z2w45vjuxg8fk00r": 1.47238742}' fee_rate=1 >> ~/report.txt
#btc -rpcwallet=bank -named send outputs='{"ut1qa0ccju4pej9lvk26gthyulqjgkmd8rjdffq4vc": 1.47238742}' fee_rate=1 >> ~/report.txt
#btc -rpcwallet=bank -named send outputs='{"ut1qnekh7k0k63mfarar60tehxzklhaezf3ptjssyz": 1.47238742}' fee_rate=1 >> ~/report.txt
#btc -rpcwallet=bank -named send outputs='{"ut1qelu5sdqjpeg8vlsz7geflvpyhvx5g9d4mxult7": 1.47238742}' fee_rate=1 >> ~/report.txt
#
#echo "executed txids" > ~/report.txt
#btc -rpcwallet=bank gettransaction 68fcb4f2cf4eeab616b1f22204624e6f7bdc9bbefa8f29cf53b871a3c4a9cfd2 >> ~/report.txt
#btc -rpcwallet=bank gettransaction 9d1b90543e0a90cda2e3ec4b0167aba394f284c0549bcc2dbbaa6181d133e429 >> ~/report.txt
#btc -rpcwallet=bank gettransaction 22f88588c43e99137e8fa74f523e66d6cd7003eafdb6624aaf8678d5dfe797c0 >> ~/report.txt
#btc -rpcwallet=bank gettransaction aecc74588ac93e66aa8b71ff3a8fe8bc175da8c39750c5640a6097210f91b6c7 >> ~/report.txt
#
#
#./contract_emails_ut.sh Matt mpickens3d@gmail.com 1.47238742 ut1qnsfzalxfn2d3ml648mnuk6z2w45vjuxg8fk00r 9.89724101 10 480-262-1776 mla3360@hotmail.com 303 3845.932 68fcb4f2cf4eeab616b1f22204624e6f7bdc9bbefa8f29cf53b871a3c4a9cfd2
#./contract_emails_ut.sh Aisake aisake@gritset.com 1.47238742 ut1qa0ccju4pej9lvk26gthyulqjgkmd8rjdffq4vc 9.89724101 10 480-262-1776 mla3360@hotmail.com 303 3845.932 9d1b90543e0a90cda2e3ec4b0167aba394f284c0549bcc2dbbaa6181d133e429
#./contract_emails_ut.sh Teresa tlpickens@gmail.com 1.47238742 ut1qnekh7k0k63mfarar60tehxzklhaezf3ptjssyz 9.89724101 10 480-262-1776 mla3360@hotmail.com 303 3845.932 22f88588c43e99137e8fa74f523e66d6cd7003eafdb6624aaf8678d5dfe797c0
#./contract_emails_ut.sh Lance lanceatkinson@frontier.com 1.47238742 ut1qelu5sdqjpeg8vlsz7geflvpyhvx5g9d4mxult7 9.89724101 10 480-262-1776 mla3360@hotmail.com 303 3845.932 aecc74588ac93e66aa8b71ff3a8fe8bc175da8c39750c5640a6097210f91b6c7
#./contract_emails_ut.sh Test mqpickens@yahoo.com 1.47238742 ut1qelu5sdqjpeg8vlsz7geflvpyhvx5g9d4mxult7 9.89724101 10 480-262-1776 mla3360@hotmail.com 303 3845.932 aecc74588ac93e66aa8b71ff3a8fe8bc175da8c39750c5640a6097210f91b6c7
