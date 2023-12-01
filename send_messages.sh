#!/bin/bash
# Installing the send_messages script
if [[ $1 = "--install" ]]; then
    echo "Installing this script (send_messages) in /usr/local/sbin/"
    if [ -f /usr/local/sbin/send_messages ]; then
        echo "This script (send_messages) already exists in /usr/local/sbin!"
        read -p "Would you like to reinstall it? (y|n): "
        if [[ "${REPLY}" = "y" || "${REPLY}" = "Y" ]]; then
            sudo rm /usr/local/sbin/send_messages
        else
            exit 0
        fi
    fi
    sudo cat $0 | sudo tee /usr/local/sbin/send_messages > /dev/null
    sudo chmod +x /usr/local/sbin/send_messages

    # Prepare for send_messages logging
    sudo touch /var/log/send_messages.log
    sudo chown root:root /var/log/send_messages.log
    sudo chmod 644 /var/log/send_messages.log
    cat << EOF | sudo tee /etc/logrotate.d/send_messages
/var/log/send_messages.log {
$(printf '\t')create 644 root root
$(printf '\t')monthly
$(printf '\t')rotate 6
$(printf '\t')compress
$(printf '\t')delaycompress
$(printf '\t')postrotate
$(printf '\t')endscript
}
EOF

    # Prepare for send_messages environment file
    if [ ! -f /etc/default/send_messages.env ]; then
        read -p "EMAIL API address (e.g. \"https://api.brevo.com/v3/smtp/email\"): "; echo "API_EMAIL=\"$REPLY\"" | sudo tee /etc/default/send_messages.env > /dev/null
		read -p "SMS API address (e.g. \"https://api.brevo.com/v3/transactionalSMS/sms\"): "; echo "API_SMS=\"$REPLY\"" | sudo tee /etc/default/send_messages.env > /dev/null
        read -p "EMAIL API key to send email (e.g. \"xkeysib-05...76-9...1\"): "; echo "KEY_EMAIL=\"$REPLY\"" | sudo tee -a /etc/default/send_messages.env > /dev/null
		read -p "SMS API key to send sms (e.g. \"xkeysib-05...76-9...1\"): "; echo "KEY_SMS=\"$REPLY\"" | sudo tee -a /etc/default/send_messages.env > /dev/null
        read -p "Sender name (e.g. \"AZ Money\"): "; echo "SENDER_NAME=\"$REPLY\"" | sudo tee -a /etc/default/send_messages.env > /dev/null
        read -p "Sender email (e.g. satoshi@somemicrocurrency.com): "; echo "SENDER_EMAIL=\"$REPLY\"" | sudo tee -a /etc/default/send_messages.env > /dev/null
    else
        echo "The environment file \"/etc/default/send_messages.env\" already exits."
    fi

    exit 0
fi

# Load envrionment variables and then verify
LOG=/var/log/send_messages.log
if [[ -f /etc/default/send_messages.env ]]; then
    source /etc/default/send_messages.env
    if [[ -z $API_EMAIL || -z $API_SMS || -z $KEY_EMAIL || -z $KEY_SMS || -z $SENDER_NAME || -z $SENDER_EMAIL ]]; then
        echo ""; echo "Error! Not all variables have proper assignments in the \"/etc/default/send_messages.env\" file"
        exit 1;
    fi
else
    echo "Error! The \"/etc/default/send_messages.env\" environment file does not exist!"
    echo "Run this script with the --install parameter."
    exit 1
fi

NAME=$1; EMAIL=$2; SUBJECT=$3; MESSAGE=$4

if [[ -z $NAME || -z $EMAIL || -z $SUBJECT || -z $MESSAGE ]]; then
    echo "Error! Insufficient Parameters!"
    exit 1
fi

# Replace every character not in the REGEX expression. Helps prevent JSON errors.
MESSAGE=$(echo $MESSAGE | sed 's/[^A-Za-z0-9.<>(),$/"\¢#@`:&;?!+-]/ /g')

generate_post_data()
{
    cat <<EOF
    {
            "sender":{
            "name":"${SENDER_NAME}",
            "email":"${SENDER_EMAIL}"
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

# Sending email
RESPONSE=$(curl --request POST --url $API_EMAIL --header 'accept: application/json' --header "api-key: ${KEY_EMAIL}" --header 'content-type: application/json' --data "$(generate_post_data)")

# Log entry
echo "$(date) - $RESPONSE; Name=\"$NAME\"; Email=\"$EMAIL\"; Subject=\"$SUBJECT\"; Message=\"${MESSAGE:0:100}...\"" | sudo tee -a $LOG






curl --request POST \
     --url https://api.brevo.com/v3/transactionalSMS/sms \
     --header 'accept: application/json' \
	 --header 'content-type: application/json' \
     --data '
{
  "sender": "BTC of AZ",
  "recipient": "${PHONE}",
  "content": "${MESSAGE}",
  "tag": "accountValidation",
  "webUrl": "http://requestb.in/173lyyx1",
  "unicodeEnabled": true,
  "organisationPrefix": "MyCompany"
}
'



generate_post_data()
{
    cat <<EOF
    {
		"sender": "${SENDER_NAME}",
        "recipient": "${PHONE}",
        "content":"${MESSAGE}"
    }
EOF
}

# Sending sms
RESPONSE=$(curl --request POST --url $API_SMS --header 'accept: application/json' --header "api-key: ${KEY_SMS}" --header 'content-type: application/json' --data "$(generate_post_data)")



