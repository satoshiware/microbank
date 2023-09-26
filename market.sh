#!/bin/bash
# Installing the market script
if [[ $1 = "--install" ]]; then
    echo "Installing this script (market) in /usr/local/sbin/"
    if [ -f /usr/local/sbin/market ]; then
        echo "This script (market) already exists in /usr/local/sbin!"
        read -p "Would you like to reinstall it? (y|n): "
        if [[ "${REPLY}" = "y" || "${REPLY}" = "Y" ]]; then
            sudo rm /usr/local/sbin/market
        else
            exit 0
        fi
    fi
    sudo cat $0 | sudo tee /usr/local/sbin/market > /dev/null
    sudo chmod +x /usr/local/sbin/market

    # Prepare for market logging
    sudo touch /var/log/market.log
    sudo chown root:root /var/log/market.log
    sudo chmod 644 /var/log/market.log
    cat << EOF | sudo tee /etc/logrotate.d/market
/var/log/market.log {
$(printf '\t')create 644 root root
$(printf '\t')monthly
$(printf '\t')rotate 6
$(printf '\t')compress
$(printf '\t')delaycompress
$(printf '\t')postrotate
$(printf '\t')endscript
}
EOF

elif [[ $1 = "--getmicrorate" ]]; then
    old_satrate=$2
    if [ ! -z $old_satrate ]; then
        echo $((old_satrate + 1))
    fi

elif [[ $1 = "--getusdrate" ]]; then # Get btc/usd exchange rates from a popular exchanges
    BTCUSD=$(curl -s https://api.coinbase.com/v2/prices/BTC-USD/spot | jq '.data.amount') # Coinbase BTC/USD Price
#   BTCUSD=$(curl -s "https://api.kraken.com/0/public/Ticker?pair=BTCUSD" | jq '.result.XXBTZUSD.a[0]') # Kraken BTC/USD Price

    BTCUSD=${BTCUSD//\"/} # Remove quotes
    echo $(awk -v btcusd=$BTCUSD 'BEGIN {printf("%.3f\n", 100000000 / btcusd)}') # Convert to $ATS

else
    echo "Method not found"
    echo "Run script with \"--help\" flag"
fi