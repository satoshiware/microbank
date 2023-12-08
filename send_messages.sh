#!/bin/bash

# Load envrionment variables and then verify
LOG=/var/log/send_messages.log
if [[ -f /etc/default/send_messages.env && ! ($1 == "-i" || $1 == "--install") ]]; then
    source /etc/default/send_messages.env
    if [[ -z $API_EMAIL || -z $API_SMS || -z $KEY_EMAIL || -z $KEY_SMS || -z $SENDER_EMAIL_NAME || -z $SENDER_EMAIL || -z $SENDER_SMS_PHONE ]]; then
        echo ""; echo "Error! Not all variables have proper assignments in the \"/etc/default/send_messages.env\" file"
        exit 1;
    fi
elif [[ $1 == "-i" || $1 == "--install" ]]; then echo ""
else
    echo "Error! The \"/etc/default/send_messages.env\" environment file does not exist!"
    echo "Run this script with the --install parameter."
    exit 1
fi

# See which send_messages parameter was passed and execute accordingly
if [[ $1 = "-h" || $1 = "--help" ]]; then # Show all possible paramters
    cat << EOF
    Options:
      -h, --help        Display this help message and exit
      -i, --install     Install this script (send_messages) in /usr/local/sbin
      -s, --sms         Send SMS (160 Characters Max)
                        Parameters: PHONE  MESSAGE
      -m, --email       Send Email
                        Parameters: RECIPIENTS_NAME  EMAIL  SUBJECT  MESSAGE

----- Locations -------------------------------------------------------------------------------------------------------------
      This:                     /usr/local/sbin/send_messages
      Source Variables          /etc/default/send_messages.env
      Log:                      /var/log/send_messages.log
EOF

# Installing the send_messages script
elif [[ $1 = "-i" || $1 = "--install" ]]; then
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
    sudo cat $0 | sed '/Install this script (send_messages)/d' | sudo tee /usr/local/sbin/send_messages > /dev/null
    sudo sed -i 's/$1 = "-i" || $1 = "--install"/"a" = "b"/' /usr/local/sbin/send_messages # Make it so this code won't run again in the newly installed script.
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
        read -p "SMS API key to send sms (e.g. \"KEY017D...b3_5z...cJ\"): "; echo "KEY_SMS=\"$REPLY\"" | sudo tee -a /etc/default/send_messages.env > /dev/null
        read -p "Sender email name (e.g. \"AZ Money\"): "; echo "SENDER_EMAIL_NAME=\"$REPLY\"" | sudo tee -a /etc/default/send_messages.env > /dev/null
        read -p "Sender email (e.g. satoshi@somemicrocurrency.com): "; echo "SENDER_EMAIL=\"$REPLY\"" | sudo tee -a /etc/default/send_messages.env > /dev/null
        read -p "Sender SMS phone (add country prefix; no spaces) (e.g. \"14809198257\"): "; echo "SENDER_SMS_PHONE=\"$REPLY\"" | sudo tee -a /etc/default/send_messages.env > /dev/null
    else
        echo "The environment file \"/etc/default/send_messages.env\" already exits."
    fi

elif [[ $1 = "-s" || $1 = "--sms" ]]; then # Send SMS (160 Characters Max)
    # Tested with telnyx.com phone service
    PHONE=$2; MESSAGE=$3

    # Verify phone number is good for the U.S.
    PHONE="1${PHONE//-}"; PHONE="${PHONE//\(}"; PHONE="${PHONE//\)}"; PHONE="${PHONE// }"
    REGEX='^[0-9]+$'
    if ! [[ $PHONE =~ $REGEX ]]; then
        echo "Error!! Phone number contains non-numeric characters!"; exit 1
    elif [[ ${#PHONE} -ne '11' ]]; then
        echo "Error!! Phone number provided contains too many or too little digits (target is 10 for U.S.)!"; exit 1
    fi

    generate_post_sms_data()
    {
        cat <<EOF
        {
            "type": "MMS",
            "from": "+${SENDER_SMS_PHONE}",
            "to": "+${PHONE}",
            "text": "${MESSAGE}"
        }
EOF
    }

    # Sending MMS ~1500 characters (~500 w\ unicode)
    RESPONSE=$(curl --request POST --url $API_SMS --header 'Content-Type: application/json' --header "Accept: application/json" --header "Authorization: Bearer ${KEY_SMS}" --data "$(generate_post_sms_data)")
    echo $RESPONSE

    # Log entry
    echo "$(date) - $RESPONSE" | sudo tee -a $LOG

elif [[ $1 = "-m" || $1 = "--email" ]]; then # Send Email
    # Tested with brevo.com email service
    NAME=$2; EMAIL=$3; SUBJECT=$4; MESSAGE=$5

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
                "name":"${SENDER_EMAIL_NAME}",
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
    echo $RESPONSE

    # Log entry
    echo "$(date) - $RESPONSE; Name=\"$NAME\"; Email=\"$EMAIL\"; Subject=\"$SUBJECT\"; Message=\"${MESSAGE:0:100}...\"" | sudo tee -a $LOG

else
    echo "Method not found"
    echo "Run script with \"--help\" flag"
    echo "Script Version 0.10"
fi