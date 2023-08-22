#!/bin/bash
SQ3DBNAME=btcofaz.db

INITIALREWARD=1500000000
EPOCHBLOCKS=1440                #
HALVINGINTERVAL=262800          # Number of blocks in before the next halving
HASHESPERCONTRACT=10000000000   # Hashes per second for each contract
BLOCKINTERVAL=120               # Number of seconds (typically) between blocks

BTC="sudo -u bitcoin /usr/bin/bitcoin-cli -micro -datadir=/var/lib/bitcoin -conf=/etc/bitcoin.conf"
UNLOCK="$BTC -rpcwallet=bank walletpassphrase qT0c6h2WtvyzKms1xEEMBo0xF0LZJ5F1 600"

# TODO LIST ##################################
# Hide key in alias (unlockwallts) and hide it here too
# Are you gonna add up the fees and consider those in the "--epoch" routine?
# The fee rate on the transaction is fixed. What can we do to make it dynamic
# Add rollback for --epoch db insert in case something goes wrong
# EMAIL and update LOG after each epoch update
# Send routine
#### Check if there is enough money, before sending (LOG and email on error)
#### Verify TXID, Print TXID to the LOG File (ALL PASS THROUGHS), EXIT if TXID was not good and verify balance did not change if so, bigger SECOND WORST CASE!!!!.
#### If all went well, and there is still more txs to make then recursivly call routine. Other wise, EMAIL and LOG.
#### Check for worst case. TXID is valid, but the DB was not updated correctly: Fill in all TXID that null with error, LOG, EMAIL
# Confirm routine. reread the newly updated database. Update LOG and EMAIL.

# DEBUG/USEFULL COMMANDS ##################################
# Remove most recent payout epoch and all transactions that have not been processed
#### sqlite3 $SQ3DBNAME "DELETE FROM payouts WHERE epoch_period = (SELECT MAX(epoch_period) FROM payouts);"
#### sqlite3 $SQ3DBNAME "DELETE FROM txs WHERE txid is NULL;"
# sqlite3 $SQ3DBNAME "DELETE FROM txs WHERE tx_id = (SELECT MAX(tx_id) FROM txs);" # Remove last tx
# sqlite3 $SQ3DBNAME "UPDATE payouts SET notes = \"azcoin = 245 sats\" WHERE epoch_period = (SELECT MAX(epoch_period) FROM payouts);"
# sqlite3 $SQ3DBNAME "UPDATE txs SET notified = 1 WHERE notified IS NULL;"
# sqlite3 $SQ3DBNAME ".mode columns" "SELECT * FROM payouts WHERE epoch_period = (SELECT MAX(epoch_period) FROM payouts);" # The latest epoch added to the DB
# sqlite3 $SQ3DBNAME ".mode columns" "SELECT * FROM txs WHERE epoch_period = (SELECT MAX(epoch_period) FROM payouts);" # The latest transactions added to the DB

# See which payouts parameter was passed and execute accordingly
if [[ $1 = "-h" || $1 = "--help" ]]; then # Show all possible paramters
    cat << EOF
    Options:
      -h, --help        Display this help message and exit
      -e, --epoch       Look for next difficulty epoch and prepare the DB for next round of payouts
      -s, --send        Send the Money (a 2nd NUMBER parameter generates NUMBER of outputs; default = 1)
      -c, --confirm     Confirm the sent payouts are confirmed in the blockchain; update the DB
      -d, --dump        Show all the contents of the database
      -a, --accounts    Show all active accounts (NO association, master, contact, update frequencies, address, or notes)
      -p, --payouts     Show all payouts thus far (a 2nd parameter will limit the NUMBER of rows displayed - in descending order)
      -t, --totals      Show total amounts for each contract (identical addresses are combinded)

      --------------------------------------------------------------------------------------
      -s, --stratum     Make p2p and stratum outbound connections (level 1 --> 2 or 2 --> 3)
      -n, --in          Configure inbound connection (Level 3 <-- 2 or 2 <-- 1)
      -p, --p2p         Make p2p inbound/outbound connections (level 3 <--> 3)
      -r, --remote      Configure inbound connection for a level 3 remote mining operation
      -o, --open        Open firewall to the stratum port for any local ip
      -y, --priority    Sets the priorities of the stratum proxy connections for a level 2 node/hub
      -v, --view        See all configured connections and view status
      -d, --delete      Delete a connection
      -f, --info        Get the connection parameters for this node
      -g, --generate    Generate micronode information file (/etc/micronode.info) with connection parameters for this node

EOF
elif [[ $1 = "-e" || $1 = "--epoch" ]]; then # Look for next difficulty epoch and prepare the DB for next round of payouts
    NEXTEPOCH=$((1 + $(sqlite3 $SQ3DBNAME "SELECT epoch_period FROM payouts ORDER BY epoch_period DESC LIMIT 1;")))
    BLOCKEPOCH=$((NEXTEPOCH * EPOCHBLOCKS))

    if [ $($BTC getblockcount) -ge $BLOCKEPOCH ]; then
        tmp=$($BTC getblock $($BTC getblockhash $BLOCKEPOCH))
        BLOCKHASH=$(echo $tmp | jq '.hash')
        BLOCKTIME=$(echo $tmp | jq '.time')
        DIFFICULTY=$(echo $tmp | jq '.difficulty')

        EXPONENT=$(awk -v eblcks=$BLOCKEPOCH -v interval=$HALVINGINTERVAL 'BEGIN {printf("%d\n", eblcks / interval)}')
        SUBSIDY=$(awk -v reward=$INITIALREWARD -v expo=$EXPONENT 'BEGIN {printf("%d\n", reward / 2 ^ expo)}')

        FEES=0

        AMOUNT=$(awk -v hashrate=$HASHESPERCONTRACT -v btime=$BLOCKINTERVAL -v subs=$SUBSIDY -v fee=$FEES -v diff=$DIFFICULTY -v eblcks=$EPOCHBLOCKS 'BEGIN {printf("%d\n", ((hashrate * btime) / (diff * 2^32)) * ((subs * eblcks) + fee))}')

        # Get array of contract_ids (from active contracts only before this epoch).
        tmp=$(sqlite3 $SQ3DBNAME "SELECT contract_id, quantity FROM contracts WHERE active=1 AND time<=$BLOCKTIME")
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
        sqlite3 $SQ3DBNAME << EOF
        PRAGMA foreign_keys = ON;
        INSERT INTO payouts (epoch_period, block_height, subsidy, total_fees, hash, block_time, difficulty, amount)
        VALUES ($NEXTEPOCH, $BLOCKEPOCH, $SUBSIDY, $FEES, $BLOCKHASH, $BLOCKTIME, $DIFFICULTY, $AMOUNT);
        INSERT INTO txs (contract_id, epoch_period, amount)
        VALUES $SQL_VALUES;
EOF

        # Query DB
        echo ""
        sqlite3 $SQ3DBNAME << EOF
.mode columns
        SELECT epoch_period, block_height, subsidy, total_fees, hash, block_time, difficulty, amount FROM payouts WHERE epoch_period = $NEXTEPOCH;
        SELECT * FROM txs WHERE epoch_period = $NEXTEPOCH;
EOF
        echo ""
    else
        echo "You have $(($BLOCKEPOCH - $($BTC getblockcount))) blocks to go for the next epoch."
    fi

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
        sqlite3 $SQ3DBNAME "UPDATE txs SET txid = $TXID, vout = $(echo $TX | jq .details[$i].vout) WHERE tx_id = ${TX_ID[i]};"
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
            sqlite3 $SQ3DBNAME "UPDATE txs SET block_height = $(echo $tmp | jq '.blockheight') WHERE txid = \"${query[i]}\";"

            # Query DB
            echo "Confirmed:"; sqlite3 $SQ3DBNAME ".mode columns" "SELECT * FROM txs WHERE txid = \"${query[i]}\";"; echo ""
        else
            echo "NOT Confirmed! TXID \"${query[i]}\" has $CONFIRMATIONS confirmations (needs 6 or more)."; echo ""
        fi
    done

elif [[  $1 = "-d" || $1 = "--dump" ]]; then # Show all the contents of the database
    sqlite3 $SQ3DBNAME ".dump"

elif [[  $1 = "-a" || $1 = "--accounts" ]]; then # Show all active accounts (NO association, master, contact, update frequencies, address, or notes)
    sqlite3 $SQ3DBNAME << EOF
.mode columns
    SELECT account_id, first_name, last_name, preferred_name, email, phone FROM accounts
EOF

elif [[  $1 = "-p" || $1 = "--payouts" ]]; then # Show all payouts thus far  (a 2nd parameter will limit the NUMBER of rows displayed - in descending order)
    if [ -z "${2}" ]; then
        LIMIT="10"
    else
        LIMIT="$2"
    fi

    sqlite3 $SQ3DBNAME ".mode columns" "SELECT * FROM payouts ORDER BY epoch_period DESC LIMIT $LIMIT"

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

elif [[  $1 = "-t" || $1 = "--testing" ]]; then # Show all payouts thus far  (a 2nd parameter will limit the NUMBER of rows displayed - in descending order)
    if [ -z "${2}" ]; then
        LIMIT=""
    else
        LIMIT="ORDER BY epoch_period DESC LIMIT $2"
    fi




#What about frequency of emails?? It get to be a real pain to diminish these. Not sure. What about idetical addresses?

#NAME or PREFERRED NAME
#CONTRACT[] PAYOUT_AMOUNT
#CONTRACT[] ADDRESS
#CONTRACT[] TOTAL
#CONTRACT[] AMOUNT
#CONTACT PHONE NUMBER
#CONTACT EMAIL
#PRICE  (SAGZ in SATS)
#PRICE (USD in SATS)
#TXID[]

#Ok, so everything should be orgainzed by the latest payout. the complexity if we combine payout emails. That could be challenging.
#Well, how about we start with

#./contract_emails_ut.sh    Matt    mpickens3d@gmail.com    1.39758747  ut1qnsfzalxfn2d3ml648mnuk6z2w45vjuxg8fk00r  4.28127646  10  480-262-1776    mla3360@hotmail.com 315 3823.405    b018af16daca5472e78d83caf9c373b543b2f2f882436f91e773e35a12ac5cbd


#Ok, we can mark it each TX that an email notification has not been sent. That seems most logical.


    sqlite3 $SQ3DBNAME << EOF
.separator "~~"
	SELECT 
		accounts.first_name, 
		accounts.preferred_name, 
		accounts.email AS Email, 
		CAST(txs.amount as REAL) / 100000000 AS Amount, 
		contracts.micro_address AS Address,
		txs.txid AS TXID,
		contracts.quantity * $HASHESPERCONTRACT / 1000000000 AS Hashrate,
		contact
	FROM accounts, txs, contracts
	WHERE accounts.account_id = contracts.account_id AND contracts.contract_id = txs.contract_id AND txs.epoch_period = (SELECT MAX(epoch_period) FROM payouts);
EOF


    sqlite3 $SQ3DBNAME << EOF
.mode columns
	SELECT 
		contact,
		(SELECT phone FROM accounts WHERE account_id = contact)
	FROM accounts
EOF


SELECT contact FROM accounts
	
	WHERE accounts.account_id = contracts.account_id AND contracts.contract_id = txs.contract_id AND txs.epoch_period = (SELECT MAX(epoch_period) FROM payouts);
	
	
	
	
	

(SELECT phone FROM accounts WHERE account_id = p.accounts.contact)


(SELECT phone FROM accounts WHERE account_id = p.contact)

SELECT phone FROM accounts WHERE account_id = accounts.contact
accounts.contact


    sqlite3 $SQ3DBNAME "SELECT contact FROM accounts.contact"
	
	
	sqlite3 $SQ3DBNAME "SELECT phone, email FROM accounts WHERE account_id = (SELECT contact FROM accounts)"
	WHERE accounts.account_id = contracts.account_id AND contracts.contract_id = txs.contract_id AND txs.epoch_period = (SELECT MAX(epoch_period) FROM payouts);
EOF



phone	email	coin(sats)	usd(sats)
# CAST(SUM(txs.amount) as REAL) / 100000000 AS Totals






#accounts.disabled
#accounts.account_id

#contracts.contract_id
#contracts.account_id
#contracts.sale_id
#contracts.reference_id
#  contracts.quantity
#        contracts.active
#        contracts.micro_address
#       sales.sale_id



#        txs.tx_id INTEGER PRIMARY KEY,
#        txs.contract_id INTEGER NOT NULL,
#        txs.epoch_period INTEGER NOT NULL,
#        txs.txid BLOB,
#        txs.vout INTEGER,
#        txs.amount INTEGER NOT NULL,

#       txs.block_height INTEGER,

#        FOREIGN KEY (contract_id) REFERENCES contracts (contract_id),
#        FOREIGN KEY (epoch_period) REFERENCES payouts (epoch_period)




else
    echo "Method not found"
    echo "Run script with \"--help\" flag"
fi