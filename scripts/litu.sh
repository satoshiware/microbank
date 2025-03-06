#!/bin/bash

##### Future Todos ##### <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
#    Watchtowers are automatically integrated with all trusted (peer bank) channel partners.
#        The Eye of Satoshi (rust-teos) Watchtower: https://github.com/talaia-labs/rust-teos
#        Watchtower Client: https://github.com/talaia-labs/rust-teos
#    Convert all private channels to hosted private channels when the Core Lightning software has advanced sufficiently.
#    Remove the bitcoind install from this VM Instance (there may be a plugin for this)
#        Note: The current Core Lightning software (2/18/25) requires a local bitcoind instance running for bitcoin-cli access
#        (even though it's still connected to this bank's full bitcoin node). On future updates, it may no longer be necessary.
#    Allow for reserve requirements (on this end) to be 0 for incomming connnections. Implement this on other lightning nodes as well.

# Make sure we are not running as root, but that we have sudo privileges.
if [ "$(id -u)" = "0" ]; then
   echo "This script must NOT be run as root (or with sudo)!"
   exit 1
elif [ "$(sudo -l | grep '(ALL : ALL) ALL' | wc -l)" = 0 ]; then
   echo "You do not have enough sudo privileges!"
   exit 1
fi

# Universal envrionment variables
LNCLI=$(cat /etc/bash.bashrc | grep "alias lncli=" | cut -d "\"" -f 2)

# See which litu parameter was passed and execute accordingly
if [[ $1 = "--help" ]]; then # Show all possible paramters
    cat << EOF
    Options:
      --help            Display this help message and exit
      --install         Install (or upgrade) this script (litu) in /usr/local/sbin (/satoshiware/microbank/scripts/litu.sh)  <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
      --generate        (Re)Generate(s) the environment file (w/ needed constants) for this utility in /etc/default/litu.env <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
      --ip_update       For nodes without a static IP (using dynamic DNS), this will update the ip that's announced by the lightning node. !!!!!!!!!! Not done yet !!!!!!!!!!!!!!!!!!!!!!!
      --global_channel  Establish a "global" channel to improve liquidity world-wide (w/ 0 reserves): \$PEER_ID  \$AMOUNT (Note: min-emergency-msat is set to 100000000)
      --peer_channel    Establish a "peer" channel to a "trusted" local bank (w/ 0 reserves): \$PEER_ID  \$AMOUNT (Note: min-emergency-msat is set to 100000000)
      --private_channel Establish a "private" channel with an internal Core Lightning node: \$PEER_ID  \$LOCAL_IP_ADDRESS  \$AMOUNT (Note: min-emergency-msat is set to 100000000)
      --summary         Produce summary of all the channels <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<  Add extra infor to the local file <<<<<<<<<<<<<<<<<<<< What about unsolicited incomming channels??? <<<<<<<<<<<<<<<<<<<<<<< Add filter option??? Probably<<<<
      --update_fees     Change the channel % fee: [\$SHORT_CHANNEL_ID | \$CHANNEL_ID | \$PEER_ID]  \$FEE_RATE (e.g. 1000 = 0.1% fee)
      --msats           Convert a figure in mSATS and display it in the form of BTC.SATS_mSATS: \$AMOUNT_MSATS

Files:
    The IDs for "global" channels are stored in the file /var/log/lightningd/global_channels
    The IDs for "peer" channels are stored in the file /var/log/lightningd/peer_channels
    The IDs AND IPs for "private" channels are stored in the file /var/log/lightningd/private_channels

Useful Commands:
    lncli getinfo                   # See the info' on this node
    lncli listnodes                 # Show all nodes (and info') on the lightning network
    lncli listnodes \$PEER_ID        # Get info' on another (non-private) node ????????????????????????????????????????????????????? how do we see the private node information?????? It's not exposed to the gossip channel.
    lncli listpeers                 # Show all nodes that share a connection with this node

    [on-chain wallet]
    lncli newaddr                   # Generates a new address which can subsequently be used to fund channels managed by the Core Lightning node
    lncli listaddresses             # List of all Bitcoin addresses that have been generated and issued by the Core Lightning node up to the current date
    lncli bkpr-listbalances         # List of all current and historical account balances both on-chain and channel balances
    lncli withdraw \$ADDRESS \$AMOUNT # Send funds from Core Lightning's internal on-chain wallet to a given \$ADDRESS.
                                    # The \$AMOUNT (msat, sats [default], btc, or "all") to be withdrawn from the internal on-chain wallet.
                                    # When using "all" for the \$AMOUNT, it will leave the at least min-emergency-msat as change if there are any open (or unsettled) channels.
    [channels]
    lncli bkpr-listbalances         # List of all current and historical account balances both on-chain and channel balances
    lncli listpeerchannels          # Return a list of this node's channels
    lncli listpeerchannels \$PEER_ID # Filter the list of this node's channels by a connected node's id
    lncli close \$ID                 # Attempts to close the channel cooperatively or unilaterally after unilateraltimeout (default: 48 hours) [\$ID = \$SHORT_CHANNEL_ID | \$CHANNEL_ID | \$PEER_ID]

    [payments]
    lncli pay <bolt11>              # Pay a bolt11 invoice

    [invoices]
    lncli invoice $AMOUNT_MSAT  $LABEL  $DESCRIPTION # The invoice RPC command creates the

    lncli invoice 1000000 $(date +%s) "Testing"


    lncli pay lnbc100n1pnu3u8xsp566guymjqlja26fu3ly45qm88qlazcanlv2l2udyg8ar2sthjlpuspp59p4m5s87upslxskh03uq3p08pg6fk6q9vlk06y39y6kfh30smuesdqv23jhxarfdensxqyjw5qcqpjrzjqfsy87natzv9khg5thj89m2vxvr0cnnjdu57z0ddhyvf6rrcgkfhh5accpaggxg3huqqqqqqqqqqqqqqyg9qxpqysgqed5um0gm3ex7uvmg9nzjnu0msgkt4wv8z20w2447wxkmff4juv3zh6ntud4vyxk2rxrwh92g6tfe7dmwjhcgvzv6ch46nm7famj0p4qp80ug0e

                invoice amount_msat label description [expiry] [fallbacks] [preimage] [exposeprivatechannels] [cltv] [deschashonly]


################################# Some maybe useful stuff todo ############################################
list Nodes IDs with incomming channel and basic information regarding their channels. Amount and balances.

Goals:
    Generate invoice for a specific amount
    Generate bolt12 invoice for arbitrary amount that can be paid infinite times.
    Send some money
EOF

elif [[ $1 == "--install" ]]; then # Install (or upgrade) this script (litu) in /usr/local/sbin (/satoshiware/microbank/scripts/litu.sh)
    echo "Installing this script (litu) in /usr/local/sbin/"
    if [ -f /usr/local/sbin/litu ]; then
        echo "This script (litu) already exists in /usr/local/sbin!"
        read -p "Would you like to upgrade it? (y|n): "
        if [[ "${REPLY}" = "y" || "${REPLY}" = "Y" ]]; then
            sudo rm /usr/local/sbin/litu
            cd ~; git clone https://github.com/satoshiware/microbank
            bash ~/microbank/scripts/litu.sh --install
            rm -rf microbank
            exit 0
        else
            exit 0
        fi
    fi

    sudo cat $0 | sudo tee /usr/local/sbin/litu > /dev/null
    sudo chmod +x /usr/local/sbin/litu

    ## Install cron jobs here: <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
        # during the install, create cronjob that sends summery (e.g. analytics, channel balances, etc.)
            # Would the bookkeeper or accounting plugin help??
        # during the install, create cronjob that checks balances and sends alerts when balances become low
        # during the install, create cronjob that tries to balance channels.

elif [[ $1 == "--ip_update" ]]; then # For nodes without a static IP (using dynamic DNS), this will update the ip that's announced by the lightning node.
    echo ""

elif [[ $1 == "--global_channel" ]]; then # Establish a "global" channel to improve liquidity world-wide (0 reserve)
    PEER_ID=$2; AMOUNT=$3

    # Input checking
    if [[ -z $PEER_ID || -z $AMOUNT ]]; then
        echo ""; echo "Error! Not all variables (PEER_ID & AMOUNT) have proper assignments"
        exit 1
    fi

    $LNCLI connect $PEER_ID; sleep 2
    RESULT=$($LNCLI fundchannel -k id=$PEER_ID amount=$AMOUNT reserve=0)

    echo $RESULT

    # On success, add the PEER_ID to the global_channels file without duplicates
    if [[ $RESULT != *"code"* ]]; then # If no error "code" was thrown then assume success
        if ! sudo grep -Fxq $PEER_ID /var/log/lightningd/global_channels 2> /dev/null; then
            echo $PEER_ID | sudo -u lightning tee -a /var/log/lightningd/global_channels
        fi
    fi

elif [[ $1 == "--peer_channel" ]]; then # Establish a "peer" channel to a trusted local bank (w/ 0 reserves): $PEER_ID  $AMOUNT
    PEER_ID=$2; AMOUNT=$3

    # Input checking
    if [[ -z $PEER_ID || -z $AMOUNT ]]; then
        echo ""; echo "Error! Not all variables (PEER_ID & AMOUNT) have proper assignments"
        exit 1
    fi

    $LNCLI connect $PEER_ID; sleep 2
    RESULT=$($LNCLI fundchannel -k id=$PEER_ID amount=$AMOUNT reserve=0)

    echo $RESULT

    # On success, add the PEER_ID to the peer_channels file without duplicates
    if [[ $RESULT != *"code"* ]]; then # If no error "code" was thrown then assume success
        if ! sudo grep -Fxq $PEER_ID /var/log/lightningd/peer_channels 2> /dev/null; then
            echo $PEER_ID | sudo -u lightning tee -a /var/log/lightningd/peer_channels
        fi
    fi

elif [[ $1 == "--private_channel" ]]; then # Establish a "private" channel with an internal Core Lightning node: \$PEER_ID  \$LOCAL_IP_ADDRESS  \$AMOUNT
    PEER_ID=$2; LOCAL_IP_ADDRESS=$3; AMOUNT=$4

    # Input checking
    if [[ -z $PEER_ID || -z $LOCAL_IP_ADDRESS || -z $AMOUNT ]]; then
        echo ""; echo "Error! Not all variables (PEER_ID, LOCAL_IP_ADDRESS, & AMOUNT) have proper assignments"
        exit 1
    fi

    $LNCLI connect $PEER_ID $LOCAL_IP_ADDRESS; sleep 2
    RESULT=$($LNCLI fundchannel -k id=$PEER_ID amount=$AMOUNT reserve=0 announce=false)

    echo $RESULT

    # On success, add the PEER_ID to the private_channels file without duplicates
    if [[ $RESULT != *"code"* ]]; then # If no error "code" was thrown then assume success
        if ! sudo grep -Fxq "$PEER_ID $LOCAL_IP_ADDRESS" /var/log/lightningd/private_channels 2> /dev/null; then
            echo "$PEER_ID $LOCAL_IP_ADDRESS" | sudo -u lightning tee -a /var/log/lightningd/private_channels
        fi
    fi

elif [[ $1 == "summary" ]]; then # Produce summary of all the channels
    echo "Global Connections:"
    if [[ -f "/var/log/lightningd/global_channels" ]]; then # Check if the file exists
        # Loop through the file Peer ID by Peer ID
        while IFS= read -r peer_id; do
            echo "    $($LNCLI listnodes $peer_id | jq -r .nodes[0].alias) (ALIAS):"
            echo "          Peer ID: $peer_id"
            echo "          Color: $($LNCLI listnodes $peer_id | jq -r .nodes[0].color)"

            count=$($LNCLI listpeerchannels $peer_id | jq '.channels | length') # Get the number of channels
            for (( i=0; i<count; i++ )); do # Loop through each channel
                echo "          Short (Long) Channel ID: $($LNCLI listpeerchannels $peer_id | jq .channels[$i] | jq -r .short_channel_id) ($($LNCLI listpeerchannels $peer_id | jq .channels[0] | jq -r .channel_id))"
                echo "              Connected:                $($LNCLI listpeerchannels $peer_id | jq .channels[$i] | jq -r .peer_connected)"
                echo "              Local Funds (msats):      $($LNCLI listpeerchannels $peer_id | jq .channels[$i] | jq -r .funding.local_funds_msat)"
                echo "              Remote Funds (msats):     $($LNCLI listpeerchannels $peer_id | jq .channels[$i] | jq -r .funding.remote_funds_msat)"
            done
            echo ""
        done < "/var/log/lightningd/global_channels"
    fi

    echo "Peer Connections (w/ Trusted Banks):"
    if [[ -f "/var/log/lightningd/peer_channels" ]]; then # Check if the file exists
        # Loop through the file Peer ID by Peer ID
        while IFS= read -r peer_id; do
            echo "    $($LNCLI listnodes $peer_id | jq -r .nodes[0].alias) (ALIAS):"
            echo "          Peer ID: $peer_id"
            echo "          Color: $($LNCLI listnodes $peer_id | jq -r .nodes[0].color)"

            count=$($LNCLI listpeerchannels $peer_id | jq '.channels | length') # Get the number of channels
            for (( i=0; i<count; i++ )); do # Loop through each channel
                echo "          Short (Long) Channel ID: $($LNCLI listpeerchannels $peer_id | jq .channels[$i] | jq -r .short_channel_id) ($($LNCLI listpeerchannels $peer_id | jq .channels[0] | jq -r .channel_id))"
                echo "              Connected:                $($LNCLI listpeerchannels $peer_id | jq .channels[$i] | jq -r .peer_connected)"
                echo "              Direction (0=Out; 1=In):  $($LNCLI listpeerchannels $peer_id | jq .channels[$i] | jq -r .direction)"
                echo "              Local Funds (msats):      $($LNCLI listpeerchannels $peer_id | jq .channels[$i] | jq -r .funding.local_funds_msat)"
                echo "              Remote Funds (msats):     $($LNCLI listpeerchannels $peer_id | jq .channels[$i] | jq -r .funding.remote_funds_msat)"
            done
            echo ""
        done < "/var/log/lightningd/peer_channels"
    fi

    echo "Private Connections:"
    if [[ -f "/var/log/lightningd/private_channels" ]]; then # Check if the file exists
        # Loop through the file Peer ID by Peer ID
        while IFS= read -r peer_id; do
            peer_id=$(echo $peer_id | cut -d " " -f 1)
            echo "    $($LNCLI listnodes $peer_id | jq -r .nodes[0].alias) (ALIAS):"
            echo "          Peer ID: $peer_id"
            echo "          Color: $($LNCLI listnodes $peer_id | jq -r .nodes[0].color)"

            count=$($LNCLI listpeerchannels $peer_id | jq '.channels | length') # Get the number of channels
            for (( i=0; i<count; i++ )); do # Loop through each channel
                echo "          Short (Long) Channel ID: $($LNCLI listpeerchannels $peer_id | jq .channels[$i] | jq -r .short_channel_id) ($($LNCLI listpeerchannels $peer_id | jq .channels[0] | jq -r .channel_id))"
                echo "              Connected:                $($LNCLI listpeerchannels $peer_id | jq .channels[$i] | jq -r .peer_connected)"
                echo "              Local Funds (msats):      $($LNCLI listpeerchannels $peer_id | jq .channels[$i] | jq -r .funding.local_funds_msat)"
                echo "              Remote Funds (msats):     $($LNCLI listpeerchannels $peer_id | jq .channels[$i] | jq -r .funding.remote_funds_msat)"
            done
            echo ""
        done < "/var/log/lightningd/private_channels"
    fi

elif [[ $1 == "--update_fees" ]]; then # Change the fee of a channel
    PEER_SHORT_CHANNEL_ID=$2 # This parameter contains the "Short Channel ID", Channel ID, or Peer ID (all channels with this given peer).
    FEE_RATE=$3 # Fee added proportionally (per-millionths) to any routed payment volume (e.g. 1000 = 0.1% fee).

    # Input checking
    if [[ -z $PEER_CHANNEL_ID || -z $FEE_RATE ]]; then
        echo ""; echo "Error! Insufficient parameters passed to this routine!"
        exit 1
    fi

    $LNCLI setchannel -k id=$PEER_SHORT_CHANNEL_ID feeppm=$FEE_RATE

elif [[ $1 == "--msats" ]]; then # Convert a figure in mSATS and display it in the form of BTC.SATS_mSATS: $AMOUNT_MSATS
    AMOUNT_MSATS=$2

    # Input checking
    if [[ -z $AMOUNT_MSATS ]]; then
        echo ""; echo "Error! There needs to be a parameter passed to this routine!"
        exit 1
    fi

    # Format result to have exactly 11 digits after the decimal
    result=$(awk "BEGIN {print $AMOUNT_MSATS / 100000000000}")
    formatted_result=$(printf "%.11f" $result)

    # Split into integer and decimal parts
    integer_part=$(echo $formatted_result | cut -d '.' -f 1)
    decimal_part=$(echo $formatted_result | cut -d '.' -f 2)

    # Group the decimal part with underscores
    grouped_decimal=$(echo $decimal_part | sed 's/\([0-9]\{6\}\)\([0-9]\{3\}\)$/\1_\2/')

    # Combine integer and formatted decimal parts
    echo "$integer_part.$grouped_decimal"

else
    $0 --help
    echo "Script Version 0.23"
fi