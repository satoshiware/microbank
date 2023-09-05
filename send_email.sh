#!/bin/bash
source /etc/default/payouts.env

if [[ $1 = "-i" || $1 = "--install" ]]; then # Install this script in /usr/local/sbin, the DB if it hasn't been already, and load available epochs from the blockchain
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

elif [[ $1 = "-p" || $1 = "--payouts" ]]; then # Send a payout email to a core customer
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

elif [[ $1 = "-a" || $1 = "--administrative" ]]; then # Send an administrative email
    SUBJECT=$2; MESSAGE=$3

    if [[ -z $SUBJECT || -z $MESSAGE ]]; then
        echo "Error! Insufficient Parameters!"
        exit 1
    fi

    NAME="satoshi"
    EMAIL="${ADMINISTRATOREMAIL}"
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