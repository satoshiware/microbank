#!/bin/bash
# Installing the send_email script
if [[ $1 = "--install" ]]; then
    echo "Installing this script (send_email) in /usr/local/sbin/"
    if [ -f /usr/local/sbin/send_email ]; then
        echo "This script (send_email) already exists in /usr/local/sbin!"
        read -p "Would you like to reinstall it? (y|n): "
        if [[ "${REPLY}" = "y" || "${REPLY}" = "Y" ]]; then
            sudo rm /usr/local/sbin/send_email
        else
            exit 0
        fi
    fi
    sudo cat $0 | sudo tee /usr/local/sbin/send_email > /dev/null
    sudo chmod +x /usr/local/sbin/send_email

    # Prepare for send_email logging
    sudo touch /var/log/send_email.log
    sudo chown root:root /var/log/send_email.log
    sudo chmod 644 /var/log/send_email.log
    cat << EOF | sudo tee /etc/logrotate.d/send_email
/var/log/send_email.log {
$(printf '\t')create 644 root root
$(printf '\t')monthly
$(printf '\t')rotate 6
$(printf '\t')compress
$(printf '\t')delaycompress
$(printf '\t')postrotate
$(printf '\t')endscript
}
EOF

    # Prepare for send_email environment file
    if [ ! -f /etc/default/send_email.env ]; then
        read -p "API address (e.g. \"https://api.brevo.com/v3/smtp/email\"): "; echo "API=\"$REPLY\"" | sudo tee /etc/default/send_email.env > /dev/null
        read -p "API key to send email (e.g. \"xkeysib-05...76-9...1\"): "; echo "KEY=\"$REPLY\"" | sudo tee -a /etc/default/send_email.env > /dev/null
        read -p "Sender name (e.g. \"AZ Money\"): "; echo "SENDER_NAME=\"$REPLY\"" | sudo tee -a /etc/default/send_email.env > /dev/null
        read -p "Sender email (e.g. satoshi@somemicrocurrency.com): "; echo "SENDER_EMAIL=\"$REPLY\"" | sudo tee -a /etc/default/send_email.env > /dev/null
    else
        echo "The environment file \"/etc/default/send_email.env\" already exits."
    fi

    exit 0
fi

# Load envrionment variables and then verify
LOG=/var/log/send_email.log
if [[ -f /etc/default/send_email.env ]]; then
    source /etc/default/send_email.env
    if [[ -z $API || -z $KEY || -z $SENDER_NAME || -z $SENDER_EMAIL ]]; then
        echo ""; echo "Error! Not all variables have proper assignments in the \"/etc/default/send_email.env\" file"
        exit 1;
    fi
else
    echo "Error! The \"/etc/default/send_email.env\" environment file does not exist!"
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
RESPONSE=$(curl --request POST --url $API --header 'accept: application/json' --header "api-key: ${KEY}" --header 'content-type: application/json' --data "$(generate_post_data)")

# Log entry
echo "$(date) - $RESPONSE; Name=\"$NAME\"; Email=\"$EMAIL\"; Subject=\"$SUBJECT\"; Message=\"${MESSAGE:0:100}...\"" | sudo tee -a $LOG