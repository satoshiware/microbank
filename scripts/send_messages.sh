#!/bin/bash

# Make sure we are not running as root, but that we have sudo privileges.
if [ "$(id -u)" = "0" ]; then
   echo "This script must NOT be run as root (or with sudo)!"
   exit 1
elif [ "$(sudo -l | grep '(ALL : ALL) ALL' | wc -l)" = 0 ]; then
   echo "You do not have enough sudo privileges!"
   exit 1
fi

# See which send_messages parameter was passed and execute accordingly
if [[ $1 = "--help" ]]; then # Show all possible paramters
    cat << EOF
    Options:
      --help        Display this help message and exit
      --install     Install this script (send_messages) in /usr/local/sbin (Repository: /satoshiware/microbank/scripts/send_messages.sh)
      --generate    (Re)Generate(s) the environment file (w/ needed constants) for this utility in /etc/default/send_messages.env
      --text        Send Test: PHONE  MESSAGE
      --email       Send Email: RECIPIENTS_NAME  EMAIL  SUBJECT  MESSAGE

    Log Location:   /var/log/send_messages.log
EOF

elif [[ $1 = "--install" ]]; then # Install this script (send_messages) in /usr/local/sbin (Repository: /satoshiware/microbank/scripts/send_messages.sh)
    echo "Installing this script (send_messages) in /usr/local/sbin/"
    if [ -f /usr/local/sbin/send_messages ]; then
        echo "This script (send_messages) already exists in /usr/local/sbin!"
        read -p "Would you like to upgrade it? (y|n): "
        if [[ "${REPLY}" = "y" || "${REPLY}" = "Y" ]]; then
            sudo rm /usr/local/sbin/send_messages
            cd ~; git clone https://github.com/satoshiware/microbank
            bash ~/microbank/scripts/send_messages.sh --install
            rm -rf microbank
            exit 0
        else
            exit 0
        fi
    fi

    sudo cat $0 | sudo tee /usr/local/sbin/send_messages > /dev/null
    sudo chmod +x /usr/local/sbin/send_messages

    # Prepare send_messages logging
    if [ ! -f /var/log/send_messages.log ]; then
        sudo touch /var/log/send_messages.log
        sudo chown root:root /var/log/send_messages.log
        sudo chmod 644 /var/log/send_messages.log
    fi

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

elif [[ $1 = "--generate" ]]; then # (Re)Generate(s) the environment file (w/ needed constants) for this utility in /etc/default/send_messages.env
    echo "Generating the environment file /etc/default/send_messages.env"
    if [ -f /etc/default/send_messages.env ]; then
        echo "The environment file already exists!"

        read -p "You can edit or replace the file. Would you like to edit the file? (y|n): "
        if [[ "${REPLY}" = "y" || "${REPLY}" = "Y" ]]; then sudo nano /etc/default/send_messages.env; exit 0; fi

        read -p "Would you like to replace it with a new one? (y|n): "
        if [[ "${REPLY}" = "y" || "${REPLY}" = "Y" ]]; then
            sudo rm /etc/default/send_messages.env
        else
            exit 0
        fi
    fi

    read -p "EMAIL API address (e.g. \"https://api.brevo.com/v3/smtp/email\"): "; echo "API_EMAIL=\"$REPLY\"" | sudo tee /etc/default/send_messages.env > /dev/null
    read -p "SMS API address (e.g. \"https://api.telnyx.com/v2/messages\"): "; echo "API_SMS=\"$REPLY\"" | sudo tee -a /etc/default/send_messages.env > /dev/null
    read -p "EMAIL API key to send email (e.g. \"xkeysib-05...76-9...1\"): "; echo "KEY_EMAIL=\"$REPLY\"" | sudo tee -a /etc/default/send_messages.env > /dev/null
    read -p "SMS API key to send sms (e.g. \"KEY017D...b3_5z...cJ\"): "; echo "KEY_SMS=\"$REPLY\"" | sudo tee -a /etc/default/send_messages.env > /dev/null
    read -p "Sender email name (e.g. \"AZ Money\"): "; echo "SENDER_EMAIL_NAME=\"$REPLY\"" | sudo tee -a /etc/default/send_messages.env > /dev/null
    read -p "Sender email (e.g. satoshi@btcofaz.com): "; echo "SENDER_EMAIL=\"$REPLY\"" | sudo tee -a /etc/default/send_messages.env > /dev/null
    read -p "Sender SMS phone (add country prefix; no spaces) (e.g. \"14809198257\"): "; echo "SENDER_SMS_PHONE=\"$REPLY\"" | sudo tee -a /etc/default/send_messages.env > /dev/null

    # Add link (for backup purposes) to the send_messages.env file
    ln -s /etc/default/send_messages.env ~/backup

elif [[ $1 = "--text" ]]; then # Send Text: PHONE  MESSAGE
    PHONE=$2; MESSAGE=$3

    # Verify phone number is good for the U.S.
    PHONE="1${PHONE//-}"; PHONE="${PHONE//\(}"; PHONE="${PHONE//\)}"; PHONE="${PHONE// }"
    REGEX='^[0-9]+$'
    if ! [[ $PHONE =~ $REGEX ]]; then
        echo "Error!! Phone number contains non-numeric characters!"; exit 1
    elif [[ ${#PHONE} -ne '11' ]]; then
        echo "Error!! Phone number provided contains too many or too little digits (target is 10 for U.S.)!"; exit 1
    fi

    # Verify environment file
    if [ -f /etc/default/send_messages.env ]; then
        source /etc/default/send_messages.env
        if [[ -z $API_SMS || -z $KEY_SMS || -z $SENDER_SMS_PHONE ]]; then
            echo ""; echo "Error! Not all variables have proper assignments in the \"/etc/default/send_messages.env\" file"
            exit 1;
        fi

    else
        echo "Error! The \"/etc/default/send_messages.env\" environment file does not exist!"
        echo "Run this script with the --generate parameter."
        exit 1
    fi

    # Prepare Data Packet
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
    echo "$(date) - $RESPONSE" | sudo tee -a /var/log/send_messages.log

elif [[ $1 = "--email" ]]; then # Send Email: RECIPIENTS_NAME  EMAIL  SUBJECT  MESSAGE
    NAME=$2; EMAIL=$3; SUBJECT=$4; MESSAGE=$5
    if [[ -z $NAME || -z $EMAIL || -z $SUBJECT || -z $MESSAGE ]]; then
        echo "Error! Insufficient Parameters!"
        exit 1
    fi

    if [ -f /etc/default/send_messages.env ]; then
        source /etc/default/send_messages.env
        if [[ -z $API_EMAIL || -z $KEY_EMAIL || -z $SENDER_EMAIL_NAME || -z $SENDER_EMAIL ]]; then
            echo ""; echo "Error! Not all variables have proper assignments in the \"/etc/default/send_messages.env\" file"
            exit 1;
        fi
    else
        echo "Error! The \"/etc/default/send_messages.env\" environment file does not exist!"
        echo "Run this script with the --generate parameter."
        exit 1
    fi

    # Replace every character not in the REGEX expression to prevent JSON errors.
    MESSAGE=$(echo $MESSAGE | sed 's/[^A-Za-z0-9.<>(),$/"\¢#@`:&;?!+-]/ /g')

    # Prepare Data Packet
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
    echo "$(date) - $RESPONSE; Name=\"$NAME\"; Email=\"$EMAIL\"; Subject=\"$SUBJECT\"; Message=\"${MESSAGE:0:100}...\"" | sudo tee -a /var/log/send_messages.log

else
    $0 --help
    echo "Script Version 0.133"
fi