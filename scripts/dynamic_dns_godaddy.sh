#!/bin/bash

# Make sure we are not running as root, but that we have sudo privileges.
if [ "$(id -u)" = "0" ]; then
   echo "This script must NOT be run as root (or with sudo)!"
   exit 1
elif [ "$(sudo -l | grep '(ALL : ALL) ALL' | wc -l)" = 0 ]; then
   echo "You do not have enough sudo privileges!"
   exit 1
fi

# See which dynamic_dns_godaddy parameter was passed and execute accordingly
if [[ $1 = "--help" ]]; then # Show all possible paramters
    cat << EOF
    Options:
      --help        Display this help message and exit
      --install -i  Install or update this script (dynamic_dns_godaddy) in /usr/local/sbin (/satoshiware/microbank/scripts/dynamic_dns_godaddy.sh)
      --generate    Generate a (new) environment file with the GoDaddy key, GoDaddy secret, and IPs (/etc/default/dynamic_dns_godaddy.env)
      --update      Check for an IP address change and update accordingly. After this script is installed, this routine is run hourly.
	  
	About:
		This script is used to check and update GoDaddy DNS server with the current IP address (Dynamic DNS).
		It requires the Godaddy Key and Godaddy Secret.
		Go to GoDaddy developer site to create a developer account and get your "production" key and secret:
			https://developer.godaddy.com/getstarted
		Run this utility with the --generate parameter to set the key, secret, and desired DNS addresses to be updated.
EOF

# Install or update this script (dynamic_dns_godaddy) in /usr/local/sbin (/satoshiware/microbank/scripts/dynamic_dns_godaddy.sh)
elif [[ $1 = "-i" || $1 == "--install" ]]; then
    echo "Installing this script (dynamic_dns_godaddy) in /usr/local/sbin/"
    if [ -f /usr/local/sbin/dynamic_dns_godaddy ]; then
        echo "This script (dynamic_dns_godaddy) already exists in /usr/local/sbin!"
        read -p "Would you like to upgrade it? (y|n): "
        if [[ "${REPLY}" = "y" || "${REPLY}" = "Y" ]]; then
            sudo rm /usr/local/sbin/dynamic_dns_godaddy
            cd ~; git clone https://github.com/satoshiware/microbank
            bash ~/microbank/scripts/dynamic_dns_godaddy.sh -i
            rm -rf microbank
            exit 0
        else
            exit 0
        fi
    fi

    sudo cat $0 | sudo tee /usr/local/sbin/dynamic_dns_godaddy > /dev/null
    sudo chmod +x /usr/local/sbin/dynamic_dns_godaddy

	# Add Cron Job (Every Two Hours) that will execute the "dynamic_dns_godaddy --update" command as $USER. Run "crontab -e" as $USER to see all its cron jobs.
    (crontab -l | grep -v -F "/usr/local/sbin/dynamic_dns_godaddy --update" ; echo "0 */1 * * * /usr/local/sbin/dynamic_dns_godaddy --update" ) | crontab -

elif [[ $1 = "--generate" ]]; then # Generate a (new) environment file with the GoDaddy key, GoDaddy secret, and IPs (/etc/default/dynamic_dns_godaddy.env)
    echo "Generating the environment file /etc/default/dynamic_dns_godaddy.env"
    if [ ! -f /etc/default/dynamic_dns_godaddy.env ]; then
        echo "The environment file already exists!"

        read -p "Would you like to edit the file? (y|n): "
        if [[ "${REPLY}" = "y" || "${REPLY}" = "Y" ]]; then sudo nano /etc/default/dynamic_dns_godaddy.env; exit 0; fi

        read -p "Would you like to replace it with a new one? (y|n): "
        if [[ "${REPLY}" = "y" || "${REPLY}" = "Y" ]]; then
            sudo rm /etc/default/dynamic_dns_godaddy.env
        else
            exit 0
        fi
    fi

    read -p "What is the root domain: "; echo "DOMAIN=\"$REPLY\"" | sudo tee /etc/default/dynamic_dns_godaddy.env > /dev/null
	read -p "What is the GoDaddy developer API key: "; echo "KEY=\"$REPLY\"" | sudo tee /etc/default/dynamic_dns_godaddy.env > /dev/null
	read -p "What is the GoDaddy developer API secret: "; echo "SECRET=\"$REPLY\"" | sudo tee /etc/default/dynamic_dns_godaddy.env > /dev/null

	read -p "Name of record to be updated: "; echo "RECORD=\"$REPLY\"" | sudo tee /etc/default/dynamic_dns_godaddy.env > /dev/null
	read -p "Name of record to be updated: "; echo "RECORD1=\"$REPLY\"" | sudo tee /etc/default/dynamic_dns_godaddy.env > /dev/null
	read -p "What is the name of 3rd record to be updated: "; echo "RECORD1=\"$REPLY\"" | sudo tee /etc/default/dynamic_dns_godaddy.env > /dev/null
	read -p "What is the name of the main record to be updated: "; echo "RECORD1=\"$REPLY\"" | sudo tee /etc/default/dynamic_dns_godaddy.env > /dev/null
	read -p "What is the name of the main record to be updated: "; echo "RECORD1=\"$REPLY\"" | sudo tee /etc/default/dynamic_dns_godaddy.env > /dev/null
	read -p "What is the name of the main record to be updated: "; echo "RECORD1=\"$REPLY\"" | sudo tee /etc/default/dynamic_dns_godaddy.env > /dev/null
	read -p "What is the name of the main record to be updated: "; echo "RECORD1=\"$REPLY\"" | sudo tee /etc/default/dynamic_dns_godaddy.env > /dev/null
	read -p "What is the name of the main record to be updated: "; echo "RECORD1=\"$REPLY\"" | sudo tee /etc/default/dynamic_dns_godaddy.env > /dev/null
	read -p "What is the name of the main record to be updated: "; echo "RECORD1=\"$REPLY\"" | sudo tee /etc/default/dynamic_dns_godaddy.env > /dev/null
    ########################################### What if there are more records ################################################
    
# Check for an IP address change and update accordingly. After this script is installed, this routine is run hourly.
elif [[ $1 = "--update" ]]; then 
	# Load the root domain, key, secret, and first dns record that may need to be updated
	if [[ -f /etc/default/dynamic_dns_godaddy.env ]]; then
		source /etc/default/dynamic_dns_godaddy.env
		if [[ -z $DOMAIN || -z $KEY || -z $SECRET || -z $RECORD1 ]]; then
			echo ""; echo "Error! Not all variables have proper assignments in the \"/etc/default/dynamic_dns_godaddy.env\" file"
			exit 1;
		fi
	else
		echo "Error! The \"/etc/default/payouts.env\" environment file does not exist!"
		echo "Run this script with the \"--generate\" parameter."
		exit 1;
	fi

	# Get IP address set in the DNS records @ GoDaddy
	headers="Authorization: sso-key $KEY:$SECRET"
	result=$(curl -s -X GET -H "$headers" "https://api.godaddy.com/v1/domains/$DOMAIN/records/A/$RECORD1")
	dnsIp=$(echo $result | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b")

	# Get current IP address ######################### How are we gatekeeping here????????????????????????????????????????????
	ret=$(curl -s GET "http://ipinfo.io/json")
	currentIp=$(echo $ret | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b")
	
	# Here's a list of more external sources to aquire your external IP address
	# currentIp=$(echo $(curl -s GET "http://ipinfo.io/json") | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b"))
	# currentIp=$(curl ifconfig.me)
	# currentIp=$(curl icanhazip.com)
	# currentIp=$(curl ipinfo.io/ip)
	# currentIp=$(curl api.ipify.org)
	# currentIp=$(curl ident.me)
	# currentIp=$(curl checkip.amazonaws.com)
	# currentIp=$(curl ipecho.net/plain)
	# currentIp=$(curl ifconfig.co)
	# currentIp=$(wget -qO- ifconfig.me | xargs echo)

	# Change GoDaddy DNS records with new IP address if necessary ########################################### What if there are more records ################################################
	if [ $dnsIp != $currentIp ]; then
		curl -X PUT "https://api.godaddy.com/v1/domains/$DOMAIN/records/A/$RECORD1" -H "accept: application/json" -H "Content-Type: application/json" -H "$headers" -d "[ { \"data\": \"$currentIp\", \"port\": 1, \"priority\": 0, \"protocol\": \"string\", \"service\": \"string\", \"ttl\": 600, \"weight\": 1 } ]"
	fi

else
    echo "Method not found"
    echo "Run script with \"--help\" flag"
    echo "Script Version 0.1"
fi