#!/bin/bash

echo "name, email, amount, address, txid, total, hashrate, coin(sats), coin(usd), coin(btc), total(sats), total(usd), hashrate(sats), hashrate(usd), Deposits(sats), Deposits(btc), deposits(coins), deposits(unit), phone, email"
NAME=$1; EMAIL=$2; AMOUNT=$3; ADDRESS=$4; TXID=$5; TOTAL=$6; HASHRATE=$7; COINVALUESATS=$8; COINVALUEUSD=$9; COINVALUEBTC=${10}; COINVALUETOTALSATS=${11}; COINVALUETOTALUSD=${12}; HASHPRICESATS=${13}; HASHPRICEUSD=${14}; DEPOSITSSATS=${15}; DEPOSITSBTC=${16}; DEPOSITSCOINS=${17}; DEPOSITSUNIT=${18}; CONTACTPHONE=${19}; CONTACTEMAIL=${20}

NETWORK="?? ?????"
NETWORKPREFIX="??"
DENOMINATION="????"
DENOMINATIONNAME="????"
HASHRATEUNIT="?H/s"
TXIDEXPLORER="https://microexplorer????.com/"

MEETUPLINK="https://meetup.com/????"

API="????"
KEY="????"

SENDERNAME="${NETWORK}"
SENDEREMAIL="satoshi@????.com"
SUBJECT="You mined $AMOUNT coins!"
MESSAGE=$(cat << EOF
        <html><head></head><body>
                Hi ${NAME},<br><br>

                You have successfully mined <b><u>$AMOUNT</u></b> coins on the \"${NETWORK}\" network with a hashrate of <b>${HASHRATE} ${HASHRATEUNIT}</b> to the following address:<br><br>
                <b>${ADDRESS}</b><br>
                <a href=\"${TXIDEXPLORER}${TXID}\"><u><i>${TXIDEXPLORER}${TXID}</i></u></a><br><br>
                So far, you have mined a total of <b><u>${TOTAL}</u></b> coins<sup>${NETWORKPREFIX}</sup> worth <b>${COINVALUETOTALSATS} \$ATS</b><sup>(\$${COINVALUETOTALUSD} USD)</sup>
                where each ${NETWORKPREFIX} coin is currently worth
                <b>${COINVALUESATS} \$ATS</b><sup>(\$${COINVALUEUSD} USD)</sup> or ${COINVALUEBTC} bitcoins as of this email.<br>
                <sup><i>Note: 1 coin is equivalent to 100 million ${DENOMINATION} or ${DENOMINATIONNAME}</i></sup><br><br>

                <b><u>Your Assets</u></b>
                <table>
                        <tr>
                                <td></td>
                                <td>${DEPOSITSSATS} \$ATS</td>
                                <td></td><td></td><td></td><td></td><td></td>
                                <td>(${DEPOSITSBTC} bitcoins)</td>
                        </tr><tr>
                                <td></td>
                                <td>${DEPOSITSCOINS} coins<sup>${NETWORKPREFIX}</sup></td>
                                <td></td><td></td><td></td><td></td><td></td>
                                <td>(${DEPOSITSUNIT} ${DENOMINATION})</td>
                        </tr>
                </table><br>


                <b><u>We\`re Here to Help!</u></b>
                <ul>
                        <li>
                                Want to aquire some \$ATS (bitcoins)? This digital gold is quickly becoming the next money reserve.<br>
                                We stand ready to buy your liquid assets (i.e. bullion, USD, and crypto) for \$ATS. <br>
                                <sup><i>Not availabe for extra large or high frequency purchases.</i></sup><br><br>
                        </li><li>
                                Are your friends mining AZ Money yet? Or would you like more hashing (mining) power?<br>
                                We have a modest \"industrial\" mining setup to mine on their (or your) behalf today!<br>
                                Starting Price: <b>${HASHPRICESATS} \$ATS</b><sup>(\$${HASHPRICEUSD} USD)</sup><br>
                                <sup><i>Buy in bulk for a discount.</i></sup><br><br>
                        </li><li>
                                We have <font color=blue><b><u><i>Tangible Coins/Cards</i></u></b></font> wallets. Load \`em up and pass \`em around!<br>
                                They were created just for you to help share satoshis (bitcoins) and AZ Money (saguaros) with your friends and family.<br><br>
                        </li><li>
                                Ready to trade \$ATS for SAGZ? Let\`s get togethor and make it happen!<br><br>
                        </li><li>
                                Questions or requests? Something else we could help you with? Would you like to learn more?<br>
                                Please don\`t hesitate to call, text, or email.
                        </li>
                </ul><br>

                <b><u>Contact Information</u></b><br>
                <ul>
                        <li>${CONTACTPHONE}</li>
                        <li>${CONTACTEMAIL}</li>
                </ul><br>

                <b><u>About</u></b><br>
                <ul>
                        <li>
                                This AZ Money hub was established to better help a limited amount of friends, family, and neighbors have access to all the possibilities Bitcoin and AZ Money have to offer; as well as help seed for an open banking system founded on decentralized money. It has been observed that politcial and financial systems based on centrally controlled money with a closed banking system always become hostile to individual liberty. If you want to get connected with the AZ Money network to either mine or establish your own hub, we are here for that too! Everyone joining the network helps turn the tide for a better day for all!
                        </li><li>
                                <b>Forum:</b> <u><i><a href=\"https://forum.satoshiware.org\">https://forum.satoshiware.org</a></i></u>
                        </li><li>
                                <b>Meetup:</b> <u><i><a href=\"${MEETUPLINK}\">${MEETUPLINK}</a></i></u>
                        </li>
                </ul>
        </body></html>
EOF
)

MESSAGE=$(echo $MESSAGE | sed 's/[^A-Za-z0-9.<>(),$/"\¢#@`:&;?!-]/ /g')

generate_post_data()
{
  cat <<EOF
{
   "sender":{
      "name":"${SENDERNAME}",
      "email":"${SENDEREMAIL}"
   },
   "to":[
      {
         "email":"$EMAIL",

 "name": "$NAME"
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
