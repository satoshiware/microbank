#!/bin/bash
source /etc/default/payouts.env

if [[ $1 = "--install" ]]; then # Install this script in /usr/local/sbin, the DB if it hasn't been already, and load available epochs from the blockchain
    echo "Installing this script (send_email) in /usr/local/sbin/"
    if [ ! -f /usr/local/sbin/send_email ]; then
        sudo cat $0 | sudo tee /usr/local/sbin/send_email > /dev/null
        sudo chmod +x /usr/local/sbin/send_email
    else
        echo "\"send_email\" already exists in /usr/local/sbin!"
        read -p "Would you like to uninstall it? (y|n): "
        if [[ "${REPLY}" = "y" || "${REPLY}" = "Y" ]]; then
            sudo rm /usr/local/sbin/send_email
            exit 0
        fi
    fi
    exit 0

elif [[ $1 = "--payouts" ]]; then # Send a payout email to a core customer
    NAME=$2; EMAIL=$3; AMOUNT=$4; TOTAL=$5; HASHRATE=$6; CONTACTPHONE=$7; CONTACTEMAIL=$8; COINVALUESATS=$9; USDVALUESATS=${10}; ADDRESSES=${11}; TXIDS=${12}

    if [[ -z $NAME || -z $EMAIL || -z $AMOUNT || -z $TOTAL || -z $HASHRATE || -z $CONTACTPHONE || -z $CONTACTEMAIL || -z $COINVALUESATS || -z $USDVALUESATS || -z $ADDRESSES || -z $TXIDS ]]; then
        echo "Error! Insufficient Parameters!"
        exit 1
    elif [[ ! $(echo "${ADDRESSES}" | awk '{print toupper($0)}') == *"${NETWORKPREFIX}1Q"* ]]; then
        echo "Error! Incorrect Address Type!"
        exit 1
    fi

    SUBJECT="You mined $AMOUNT coins!"

    ADDRESSES=${ADDRESSES//./<br>}
    ADDRESSES=${ADDRESSES//_0/ -- Deprecated}
    ADDRESSES=${ADDRESSES//_1/} # Active
    ADDRESSES=${ADDRESSES//_2/ -- Opened} # Active, but opened

    TXIDS=${TXIDS//./<\/li><li>}

    MESSAGE=$(cat << EOF
        <html><head></head><body>
            Hi ${NAME},<br><br>

            You have successfully mined <b><u>$AMOUNT</u></b> coins on the \"${NETWORK}\" network ${CLARIFY}with a hashrate of <b>${HASHRATE} GH/s</b> to the following address(es):<br><br>
            <b>${ADDRESSES}</b><br><br>
            So far, you have mined a total of <b><u>${TOTAL}</u></b> coins<sup>${NETWORKPREFIX}</sup> worth <b>$(awk -v total=${TOTAL} -v coinvaluesats=${COINVALUESATS} 'BEGIN {printf "%'"'"'.2f\n", total * coinvaluesats}') \$ATS </b><sup>(\$$(awk -v total=${TOTAL} -v coinvaluesats=${COINVALUESATS} -v usdvaluesats=${USDVALUESATS} 'BEGIN {printf "%'"'"'.2f\n", total * coinvaluesats / usdvaluesats}') USD)</sup> as of this email!<br><br>
            Notice! Always ensure the key(s) associated with this/these address(es) are in your possession!!
            Please reach out ASAP if you need a new savings card!<br><br>
            Please utilize our ${NETWORK} block explorer to get more details on an address or TXID: $EXPLORER<br>
            <br><hr><br>

            <b><u>Market Data</u></b> (as of this email)
            <table>
                <tr>
                    <td></td>
                    <td>\$1.00 USD</td>
                    <td></td><td></td><td></td><td></td><td></td>
                    <td>$(awk -v usdvaluesats=${USDVALUESATS} 'BEGIN {printf "%'"'"'.2f\n", usdvaluesats}') \$ATS</td>
                    <td></td><td></td><td></td><td></td><td></td>
                    <td>($(awk -v usdvaluesats=${USDVALUESATS} 'BEGIN {printf "%'"'"'.8f\n", usdvaluesats / 100000000}') bitcoins)</td>
                </tr><tr>
                    <td></td>
                    <td>1 ${NETWORKPREFIX} coin</sup></td>
                    <td></td><td></td><td></td><td></td><td></td>
                    <td>$(awk -v coinvaluesats=${COINVALUESATS} 'BEGIN {printf "%'"'"'.2f\n", coinvaluesats}') \$ATS</td>
                    <td></td><td></td><td></td><td></td><td></td>
                    <td>($(awk -v coinvaluesats=${COINVALUESATS} 'BEGIN {printf "%'"'"'.8f\n", coinvaluesats / 100000000}') bitcoins)</td>
                </tr>
            </table><br>

            <b><u>Key Terms</u></b>
            <table>
                <tr>
                    <td></td>
                    <td>\$ATS</td>
                    <td></td><td></td><td></td><td></td><td></td><td></td><td></td>
                    <td>Short for satoshis. The smallest unit in a bitcoin. There are 100,000,000 satoshis in 1 bitcoin.</td>
                </tr><tr>
                    <td></td>
                    <td>${DENOMINATION}</td>
                    <td></td><td></td><td></td><td></td><td></td><td></td><td></td>
                    <td>Short for ${DENOMINATIONNAME}. The smallest unit in an ${NETWORKPREFIX} coin. There are 100,000,000 ${DENOMINATIONNAME} in 1 ${NETWORKPREFIX} coin.</td>
                </tr>
            </table><br>

            <b><u>Contact Details</u></b><br>
            <ul>
                <li>${CONTACTPHONE}</li>
                <li>${CONTACTEMAIL}</li>
            </ul><br>

            <b><u>TXID(s):</u></b><br>
            <ul>
                <li>${TXIDS}</li>
            </ul><br>

            <b><u>We\`re Here to Help!</u></b><br>
            <ul>
                <li>Don't hesitate to reach out to purchase more mining power!!!</li>
                <li>If you’re interested in mining for yourself, ask us about the ${NETWORKPREFIX} / BTC Quarter Stick miner.</li>
                <li>To join the \"${NETWORKPREFIX} Money\" community and the discussion check out the forum @ <a href=\"https://forum.satoshiware.org\"><u><i>forum.satoshiware.org</i></u></a></li>
            </ul><br>
        </body></html>
EOF
    )

elif [[ $1 = "--epoch" ]]; then
    NEXTEPOCH=$2; TOTAL_FEES=$3; TX_COUNT=$4; TOTAL_WEIGHT=$5; MAXFEERATE=$6; qty_utxo=$7; expected_payment=$8; total_payment=$9; fee_percent_diff=${10}; bank_balance=${11}; t_payout=${12}

    if [[ -z $NEXTEPOCH || -z $TOTAL_FEES || -z $TX_COUNT || -z $TOTAL_WEIGHT || -z $MAXFEERATE || -z $qty_utxo || -z $expected_payment || -z $total_payment || -z $fee_percent_diff || -z $bank_balance || -z $t_payout ]]; then
        echo "Error! Insufficient Parameters!"
        exit 1
    fi

    NAME="satoshi"
    EMAIL="${ADMINISTRATOREMAIL}"
    SUBJECT="New Epoch Has Been Delivered!!!"
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

elif [[ $1 = "--info" ]]; then
    SUBJECT=$2; MESSAGE=$3

    if [[ -z $SUBJECT || -z $MESSAGE ]]; then
        echo "Error! Insufficient Parameters!"
        exit 1
    fi

    NAME="satoshi"
    EMAIL="${ADMINISTRATOREMAIL}"

elif [[ $1 = "--send-email" ]]; then
    NAME=$2; EMAIL=$3; SUBJECT=$4; MESSAGE=$5

    if [[ -z $NAME || -z $EMAIL || -z $SUBJECT || -z $MESSAGE ]]; then
        echo "Error! Insufficient Parameters!"
        exit 1
    fi

elif [[ $1 = "--send" ]]; then
    bank_balance=$2; total_payment=$3; total_sending=$4; post_bank_balance=$5; time=$6; batch_sz=$7; t_txids=$8

    if [[ -z $bank_balance || -z $total_payment || -z $total_sending || -z $post_bank_balance=$5 || -z $t_txids ]]; then
        echo "Error! Insufficient Parameters!"
        exit 1
    fi

    NAME="satoshi"
    EMAIL="${ADMINISTRATOREMAIL}"
    SUBJECT="All Payments have been completed successfully!!!"
    MESSAGE=$(cat << EOF
        <b>$(date) - All Payments have been completed successfully!</b><br>
        <ul>
            <li><b>Execution Time:</b> $time seconds</li>
            <li><b>Outputs Per TX:</b> $batch_sz</li>
            <li><b>Bank Balance:</b> $bank_balance (Before Sending Payments)</li>
            <li><b>Calculated Total:</b> $total_payment</li>
            <li><b>Total Sent:</b> $total_sending</li>
            <li><b>Bank Balance:</b> $post_bank_balance (After Sending Payments)</li>
        </ul><br>

        <b>DB Query (All Recent TXIDs)</b><br>
        $t_txids
EOF
    )

fi

MESSAGE=$(echo $MESSAGE | sed 's/[^A-Za-z0-9.<>(),$/"\¢#@`:&;?!-]/ /g')

generate_post_data()
{
    cat <<EOF
    {
            "sender":{
            "name":"${NETWORK}",
            "email":"${SENDEREMAIL}"
        },
        "to":[
            {
                "name": "${NAME}",
                "email":"${EMAIL}"
            }
       ],
        "subject":"${SUBJECT}",
        "htmlContent":"${MESSAGE}"
    }
EOF
}

curl --request POST \
  --url $API \
  --header 'accept: application/json' \
  --header "api-key: ${KEY}" \
  --header 'content-type: application/json' \
  --data "$(generate_post_data)"