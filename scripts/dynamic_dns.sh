#!/bin/bash

# Make sure we are not running as root, but that we have sudo privileges.
if [ "$(id -u)" = "0" ]; then
   echo "This script must NOT be run as root (or with sudo)!"
   exit 1
elif [ "$(sudo -l | grep '(ALL : ALL) ALL' | wc -l)" = 0 ]; then
   echo "You do not have enough sudo privileges!"
   exit 1
fi

# See which dynamic_dns parameter was passed and execute accordingly
if [[ $1 = "--help" ]]; then # Show all possible paramters
    cat << EOF
    Options:
      --help        Display this help message and exit
      --install     Install or update this script (dynamic_dns) in /usr/local/sbin (/satoshiware/microbank/scripts/dynamic_dns.sh)
      --generate    (Re)Generate(s) the environment file (w/ needed constants) for this utility in /etc/default/dynamic_dns.env
      --update      Check for an IP address change and update, log, and report to adminstrator via email accordingly (requires send_messages to be configured): RECIPIENTS_NAME  EMAIL
      --getip       Query freely available external services to discover external IPv4 address

    Log Location:   /var/log/dynamic_dns.log
    Supported DNS:  GoDaddy - Get your API Keys @ https://developer.godaddy.com (required subscription for GoDaddy's api to work; let's just call it NoDaddy)
                    Namecheap - Enable "Dynamic DNS" under adnvaced DNS managedment and it will provide the KEY (password)
EOF

elif [[ $1 = "--install" ]]; then # Install or update this script (dynamic_dns) in /usr/local/sbin (/satoshiware/microbank/scripts/dynamic_dns.sh)
    echo "Installing this script (dynamic_dns) in /usr/local/sbin/"
    if [ -f /usr/local/sbin/dynamic_dns ]; then
        echo "This script (dynamic_dns) already exists in /usr/local/sbin!"
        read -p "Would you like to upgrade it? (y|n): "
        if [[ "${REPLY}" = "y" || "${REPLY}" = "Y" ]]; then
            sudo rm /usr/local/sbin/dynamic_dns
            cd ~; git clone https://github.com/satoshiware/microbank
            bash ~/microbank/scripts/dynamic_dns.sh --install
            rm -rf microbank
            exit 0
        else
            exit 0
        fi
    fi

    sudo cat $0 | sudo tee /usr/local/sbin/dynamic_dns > /dev/null
    sudo chmod +x /usr/local/sbin/dynamic_dns

    # Prepare dynamic_dns logging
    if [ ! -f /var/log/dynamic_dns.log ]; then
        sudo touch /var/log/dynamic_dns.log
        sudo chown root:root /var/log/dynamic_dns.log
        sudo chmod 644 /var/log/dynamic_dns.log
    fi

elif [[ $1 = "--generate" ]]; then # (Re)Generate(s) the environment file (w/ needed constants) for this utility in /etc/default/dynamic_dns.env
    echo "Generating the environment file /etc/default/dynamic_dns.env"
    if [ -f /etc/default/dynamic_dns.env ]; then
        echo "The environment file already exists!"

        read -p "You can edit or replace the file. Would you like to edit the file? (y|n): "
        if [[ "${REPLY}" = "y" || "${REPLY}" = "Y" ]]; then sudo nano /etc/default/dynamic_dns.env; exit 0; fi

        read -p "Would you like to replace it with a new one? (y|n): "
        if [[ "${REPLY}" = "y" || "${REPLY}" = "Y" ]]; then
            sudo rm /etc/default/dynamic_dns.env
        else
            exit 0
        fi
    fi

    read -p "DNS Service (e.g. namecheap): "
    INPUT=$($0 "--${REPLY,,}" "NOIP" 2> /dev/null | grep "Script Version")
    if [[ -z $INPUT ]]; then
        echo "SERVICE=\"${REPLY,,}\"" | sudo tee /etc/default/dynamic_dns.env > /dev/null
    else
        echo "Sorry, DNS service \"${REPLY,,}\" is not available in this script"
        echo "See --help for available options"
        exit 1
    fi

    read -p "Root Domain: "; REPLY=${REPLY,,}; REPLY=${REPLY#http://}; REPLY=${REPLY#https://}; REPLY=${REPLY#www.}; echo "DOMAIN=\"$REPLY\"" | sudo tee -a /etc/default/dynamic_dns.env > /dev/null # Make lowercase and remove http(s) and www if they exist.
    read -p "API Key (Password): "; echo "KEY=\"$REPLY\"" | sudo tee -a /etc/default/dynamic_dns.env > /dev/null
    read -p "API Secret (If Available): "; echo "SECRET=\"$REPLY\"" | sudo tee -a /etc/default/dynamic_dns.env > /dev/null

    REPLY="GO"; i=1
    echo "RECORDS=()" | sudo tee -a /etc/default/dynamic_dns.env > /dev/null
    while [ ! -f $REPLY ]; do
        read -p "$i) (sub)domain to be updated (leave blank to finish): "
        if [[ $REPLY = "*" ]]; then REPLY="*."; fi # $REPLY is set to "*." as the character '*' alone will cause a binary operator error
        if [ ! -f $REPLY ]; then REPLY=$(echo $REPLY | cut -d '.' -f 1); echo "RECORDS+=('$REPLY')" | sudo tee -a /etc/default/dynamic_dns.env > /dev/null; REPLY="NA"; fi # $REPLY is set to "NA" as the character '*' alone will cause a binary operator error
        i=$(($i+1))
    done

elif [[ $1 = "--update" ]]; then # Check for an IP address change and update, log, and report to adminstrator via email accordingly (requires send_messages to be configured): RECIPIENTS_NAME  EMAIL
    # Load the root domain, key, secret, first dns record, and last known good IP address
    if [[ -f /etc/default/dynamic_dns.env ]]; then
        source /etc/default/dynamic_dns.env
        if [[ -z $SERVICE || -z $DOMAIN || -z $KEY || -z $SECRET || -z ${RECORDS[0]} ]]; then
            echo ""; echo "Error! Not all variables have proper assignments in the \"/etc/default/dynamic_dns.env\" file"
            exit 1;
        fi
    else
        echo "Error! The \"/etc/default/dynamic_dns.env\" environment file does not exist!"
        echo "Run this script with the \"--generate\" parameter."
        exit 1;
    fi

    # Log, email, and change IP if necessary
    CURRENT_IP=$($0 --getip)
    LAST_IP=$($0 "--$SERVICE")
    if [[ $CURRENT_IP == $LAST_IP ]]; then # There's no change so log only
        echo "$(date) - IP Unchaged: $LAST_IP" | sudo tee -a /var/log/dynamic_dns.log
    else # Change IP, log, and email
        response=$($0 "--$SERVICE" "$CURRENT_IP")
        echo "$(date) - IP Chaged From $LAST_IP to $CURRENT_IP" | sudo tee -a /var/log/dynamic_dns.log
        echo $response | sudo tee -a /var/log/dynamic_dns.log
        NAME=$2; EMAIL=$3
        if ! [[ -z $NAME || -z $EMAIL ]]; then
            send_messages --email $NAME $EMAIL "DNS Record(s) Updated" "Your DNS record(s) has/have been updated with your latest IP address from your ISP<br><br>$response"
        fi
    fi

elif [[ $1 = "--getip" ]]; then # Query freely available external services to discover external IPv4 address
    if [[ 0 = 1 ]]; then exit 1
    elif [[ $(curl -s -4 icanhazip.com) =~ ^(([1-9]?[0-9]|1[0-9][0-9]|2([0-4][0-9]|5[0-5]))\.){3}([1-9]?[0-9]|1[0-9][0-9]|2([0-4][0-9]|5[0-5]))$ ]]; then echo $(curl -s -4 icanhazip.com)
    elif [[ $(curl -s -4 http://dynamicdns.park-your-domain.com/getip) =~ ^(([1-9]?[0-9]|1[0-9][0-9]|2([0-4][0-9]|5[0-5]))\.){3}([1-9]?[0-9]|1[0-9][0-9]|2([0-4][0-9]|5[0-5]))$ ]]; then echo $(curl -s -4 http://dynamicdns.park-your-domain.com/getip)
    elif [[ $(curl -s -4 ifconfig.me) =~ ^(([1-9]?[0-9]|1[0-9][0-9]|2([0-4][0-9]|5[0-5]))\.){3}([1-9]?[0-9]|1[0-9][0-9]|2([0-4][0-9]|5[0-5]))$ ]]; then echo $(curl -s -4 ifconfig.me)
    elif [[ $(curl -s -4 ipinfo.io/ip) =~ ^(([1-9]?[0-9]|1[0-9][0-9]|2([0-4][0-9]|5[0-5]))\.){3}([1-9]?[0-9]|1[0-9][0-9]|2([0-4][0-9]|5[0-5]))$ ]]; then echo $(curl -s -4 ipinfo.io/ip)
    elif [[ $(curl -s -4 api.ipify.org) =~ ^(([1-9]?[0-9]|1[0-9][0-9]|2([0-4][0-9]|5[0-5]))\.){3}([1-9]?[0-9]|1[0-9][0-9]|2([0-4][0-9]|5[0-5]))$ ]]; then echo $(curl -s -4 api.ipify.org)
    elif [[ $(curl -s -4 ident.me) =~ ^(([1-9]?[0-9]|1[0-9][0-9]|2([0-4][0-9]|5[0-5]))\.){3}([1-9]?[0-9]|1[0-9][0-9]|2([0-4][0-9]|5[0-5]))$ ]]; then echo $(curl -s -4 ident.me)
    elif [[ $(curl -s -4 checkip.amazonaws.com) =~ ^(([1-9]?[0-9]|1[0-9][0-9]|2([0-4][0-9]|5[0-5]))\.){3}([1-9]?[0-9]|1[0-9][0-9]|2([0-4][0-9]|5[0-5]))$ ]]; then echo $(curl -s -4 checkip.amazonaws.com)
    elif [[ $(curl -s -4 ipecho.net/plain) =~ ^(([1-9]?[0-9]|1[0-9][0-9]|2([0-4][0-9]|5[0-5]))\.){3}([1-9]?[0-9]|1[0-9][0-9]|2([0-4][0-9]|5[0-5]))$ ]]; then echo $(curl -s -4 ipecho.net/plain)
    elif [[ $(curl -s -4 ifconfig.co) =~ ^(([1-9]?[0-9]|1[0-9][0-9]|2([0-4][0-9]|5[0-5]))\.){3}([1-9]?[0-9]|1[0-9][0-9]|2([0-4][0-9]|5[0-5]))$ ]]; then echo $(curl -s -4 ifconfig.co)
    else exit 1; fi

elif [[ $1 = "--godaddy" ]]; then # GoDaddy private routine (not in the help menu) to query or update/change the DNS record(s): IP_ADDRESS
    IP_ADDRESS=$2
    source /etc/default/dynamic_dns.env
    headers="Authorization: sso-key $KEY:$SECRET"
    if [[ -z $IP_ADDRESS ]]; then # If no IP_ADDRESS was passed then query and return the IP address from the DNS service
        result=$(curl -s -X GET -H "$headers" "https://api.godaddy.com/v1/domains/$DOMAIN/records/A/${RECORDS[0]}")
        echo $result | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b"
        exit 0
    else
        if [[ ! "$IP_ADDRESS" =~ ^(([1-9]?[0-9]|1[0-9][0-9]|2([0-4][0-9]|5[0-5]))\.){3}([1-9]?[0-9]|1[0-9][0-9]|2([0-4][0-9]|5[0-5]))$ ]]; then
            echo "Error! IP address is not a valid IPv4 addres!"
            exit 1
        fi
    fi

    # Update each DNS record
    for i in ${RECORDS[@]}; do
        curl -X PUT "https://api.godaddy.com/v1/domains/$DOMAIN/records/A/$i" -H "accept: application/json" -H "Content-Type: application/json" -H "$headers" -d "[ { \"data\": \"$IP_ADDRESS\", \"port\": 1, \"priority\": 0, \"protocol\": \"string\", \"service\": \"string\", \"ttl\": 600, \"weight\": 1 } ]"
    done

elif [[ $1 = "--namecheap" ]]; then # Namecheap private routine (not in the help menu) to query or update/change the DNS record(s): IP_ADDRESS
    IP_ADDRESS=$2
    source /etc/default/dynamic_dns.env
    if [[ -z $IP_ADDRESS ]]; then # If no IP_ADDRESS was passed then query and return the IP address from the DNS service
        HOST=${RECORDS[0]}
        if [[ $HOST = "@" ]]; then HOST=""
        elif [[ $HOST = "*" ]]; then HOST="wildcardcouldbeanything."
        else HOST="${HOST}."; fi
        getent hosts $HOST$DOMAIN | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b"
        exit 0
    else
        if [[ ! "$IP_ADDRESS" =~ ^(([1-9]?[0-9]|1[0-9][0-9]|2([0-4][0-9]|5[0-5]))\.){3}([1-9]?[0-9]|1[0-9][0-9]|2([0-4][0-9]|5[0-5]))$ ]]; then
            echo "Error! IP address is not a valid IPv4 addres!"
            exit 1
        fi
    fi

    # Update each DNS record
    for i in ${RECORDS[@]}; do
        curl -s "https://dynamicdns.park-your-domain.com/update?host=""$i""&domain=$DOMAIN&password=$KEY&ip=$IP_ADDRESS"
    done

else
    $0 --help
    echo "Script Version 0.25" # Do not remove this line or modify anything other than the version number. Script uses this to check for private DNS service routines (e.g. --godaddy)
fi