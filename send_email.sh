#!/bin/bash
source /etc/default/payouts.env

NAME=$1; EMAIL=$2; SUBJECT=$3; MESSAGE=$4

if [[ -z $NAME || -z $EMAIL || -z $SUBJECT || -z $MESSAGE ]]; then
    echo "Error! Insufficient Parameters!"
    exit 1
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