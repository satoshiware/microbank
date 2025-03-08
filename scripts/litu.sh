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
      --global_channel  Establish a "global" channel to improve liquidity world-wide (w/ 0 reserves): \$PEER_ID  \$AMOUNT_SATS (Note: min-emergency-msat is set to 0.00100000000_000)
      --peer_channel    Establish a "peer" channel to a "trusted" local bank (w/ 0 reserves): \$PEER_ID  \$AMOUNT_SATS (Note: min-emergency-msat is set to 0.00100000_000)
      --private_channel Establish a "private" channel with an internal Core Lightning node: \$PEER_ID \$LOCAL_IP_ADDRESS \$AMOUNT_SATS \$ALIAS \$COLOR (Note: min-emergency-msat is set to 0.00100000_000)
      --update_fees     Change the channel % fee: [\$SHORT_CHANNEL_ID | \$CHANNEL_ID | \$PEER_ID]  \$FEE_RATE (e.g. 1000 = 0.1% fee)
      --summary         Produce summary of all the channels <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<  Add extra infor to the local file <<<<<<<<<<<<<<<<<<<< What about unsolicited incomming channels??? <<<<<<<<<<<<<<<<<<<<<<< Add filter option??? Probably<<<<
      --msats           Convert a figure in mSATS and display it in the form of BTC.SATS_mSATS: \$AMOUNT_MSATS
      --ratio           Create a visual representation of the local vs remote balance: \$LOCAL_BALANCE  \$REMOTE_BALANCE

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
    PEER_ID=$2; AMOUNT_SATS=$3

    # Input checking
    if [[ -z $PEER_ID || -z $AMOUNT_SATS ]]; then
        echo ""; echo "Error! Not all variables (PEER_ID & AMOUNT_SATS) have proper assignments"
        exit 1
    fi

    $LNCLI connect $PEER_ID; sleep 2
    RESULT=$($LNCLI fundchannel -k id=$PEER_ID amount=$AMOUNT_SATS reserve=0)

    echo $RESULT

    # On success, add the PEER_ID to the global_channels file without duplicates
    if [[ $RESULT != *"code"* ]]; then # If no error "code" was thrown then assume success
        if ! sudo grep -Fxq $PEER_ID /var/log/lightningd/global_channels 2> /dev/null; then
            echo $PEER_ID | sudo -u lightning tee -a /var/log/lightningd/global_channels
        fi
    fi

elif [[ $1 == "--peer_channel" ]]; then # Establish a "peer" channel to a trusted local bank (w/ 0 reserves): $PEER_ID  $AMOUNT_SATS
    PEER_ID=$2; AMOUNT_SATS=$3

    # Input checking
    if [[ -z $PEER_ID || -z $AMOUNT_SATS ]]; then
        echo ""; echo "Error! Not all variables (PEER_ID & AMOUNT_SATS) have proper assignments"
        exit 1
    fi

    $LNCLI connect $PEER_ID; sleep 2
    RESULT=$($LNCLI fundchannel -k id=$PEER_ID amount=$AMOUNT_SATS reserve=0)

    echo $RESULT

    # On success, add the PEER_ID to the peer_channels file without duplicates
    if [[ $RESULT != *"code"* ]]; then # If no error "code" was thrown then assume success
        if ! sudo grep -Fxq $PEER_ID /var/log/lightningd/peer_channels 2> /dev/null; then
            echo $PEER_ID | sudo -u lightning tee -a /var/log/lightningd/peer_channels
        fi
    fi

elif [[ $1 == "--private_channel" ]]; then # Establish a "private" channel with an internal Core Lightning node: \$PEER_ID \$LOCAL_IP_ADDRESS \$AMOUNT_SATS \$ALIAS \$COLOR (Note: min-emergency-msat is set to 0.00100000_000)
    PEER_ID=$2; LOCAL_IP_ADDRESS=$3; AMOUNT_SATS=$4; ALIAS=$5; COLOR=$6

    # Input checking
    if [[ -z $PEER_ID || -z $LOCAL_IP_ADDRESS || -z $AMOUNT_SATS || -z $ALIAS || -z $COLOR ]]; then
        echo ""; echo "Error! Not all variables (PEER_ID, LOCAL_IP_ADDRESS, AMOUNT_SATS, ALIAS, & COLOR) have proper assignments"
        exit 1
    fi

    $LNCLI connect $PEER_ID $LOCAL_IP_ADDRESS; sleep 2
    RESULT=$($LNCLI fundchannel -k id=$PEER_ID amount=$AMOUNT_SATS reserve=0 announce=false)

    echo $RESULT

    # On success, add the PEER_ID to the private_channels file without duplicates
    if [[ $RESULT != *"code"* ]]; then # If no error "code" was thrown then assume success
        if ! sudo grep -Fxq "$PEER_ID $LOCAL_IP_ADDRESS" /var/log/lightningd/private_channels 2> /dev/null; then
            echo "$PEER_ID $LOCAL_IP_ADDRESS $(echo $ALIAS | tr ' ' '_') $COLOR" | sudo -u lightning tee -a /var/log/lightningd/private_channels
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

elif [[ $1 == "--summary" ]]; then # ???????????????????????????????????????????????????????????????????????????????????????????????????????????????????
    echo ""; echo "####################### Channels ########################"
    total_channel_msat=0
    closed_channels=0 # Running tally of all the closed channels so far
    local_total_global_msat=0 # Running tally of all the balances on the local side for global connections
    remote_total_global_msat=0 # Running tally of all the balances on the remote side for global connections
    local_total_anonymous_msat=0 # Running tally of all the balances on the local side for anonymous connections
    remote_total_anonymous_msat=0 # Running tally of all the balances on the remote side for anonymous connections
    total_closing_fees_msat=0 # Running tally of all the local fees required to close all the channels (i.e. put them on-chain)
    channels=$($LNCLI listpeerchannels | jq -c '.channels[]')
    while IFS= read -r channel; do # Loop through the channels and process them
        state=$(echo "$channel" | jq -r .state)
        if [[ $state == "ONCHAIN" ]]; then ((closed_channels++)); continue; fi # If this channel is closed (ONCHAIN) then skip

        peer_id=$(echo "$channel" | jq -r .peer_id)
        if grep -q $peer_id "/var/log/lightningd/global_channels"; then peer_type="global"
        elif grep -q $peer_id "/var/log/lightningd/peer_channels"; then peer_type="trusted-p2p"
        elif grep -q $peer_id "/var/log/lightningd/private_channels"; then  peer_type="private"
        else peer_type="anonymous"; fi

        peer_connected=$(echo "$channel" | jq -r .peer_connected)
        local_fee_base_msat=$(echo "$channel" | jq -r .updates.local.fee_base_msat)
        local_fee_proportional_millionths=$(echo "$channel" | jq -r .updates.local.fee_proportional_millionths)
        remote_fee_base_msat=$(echo "$channel" | jq -r .updates.remote.fee_base_msat)
        remote_fee_proportional_millionths=$(echo "$channel" | jq -r .updates.remote.fee_proportional_millionths)
        local_funds_msat=$(echo "$channel" | jq -r .funding.local_funds_msat)
        remote_funds_msat=$(echo "$channel" | jq -r .funding.remote_funds_msat)
        last_stable_connection=$(echo "$channel" | jq -r .last_stable_connection)
        short_channel_id=$(echo "$channel" | jq -r .short_channel_id)
        channel_id=$(echo "$channel" | jq -r .channel_id)
        private=$(echo "$channel" | jq -r .private)
        opener=$(echo "$channel" | jq -r .opener)
        local_balance_msat=$(echo "$channel" | jq -r .to_us_msat)
        remote_balance_msat=$((($local_funds_msat + $remote_funds_msat - $local_balance_msat))) # Calculated
        their_reserve_msat=$(echo "$channel" | jq -r .their_reserve_msat)
        our_reserve_msat=$(echo "$channel" | jq -r .our_reserve_msat)
        spendable_msat=$(echo "$channel" | jq -r .spendable_msat)
        receivable_msat=$(echo "$channel" | jq -r .receivable_msat)

        peer_id_info=$($LNCLI listnodes $peer_id)
        alias=$(echo $peer_id_info | jq -r .nodes[0].alias)
        color=$(echo $peer_id_info | jq -r .nodes[0].color)
        if [[ $peer_type == "private" ]]; then # The alias and color for private channels must be read from file
            captured_line=$(grep -m 1 "$peer_id" "/var/log/lightningd/private_channels")
            if [[ -n $captured_line ]]; then
                alias=$(echo $captured_line | cut -d " " -f 3)
                color=$(echo $captured_line | cut -d " " -f 4)
            fi
        fi
        if [[ $alias == "null" ]]; then alias="hidden"; color="hidden"; fi # Output "hidden" instead of "null"

        local_closing_fees_msat=$((($local_balance_msat - $our_reserve_msat - $spendable_msat)))
        remote_closing_fees_msat=$((($remote_balance_msat - $their_reserve_msat - $receivable_msat)))
        if [[ $local_closing_fees_msat -lt 0 ]]; then local_closing_fees_msat=0; fi
        if [[ $remote_closing_fees_msat -lt 0 ]]; then remote_closing_fees_msat=0; fi

        # Tally "Total Channel Amount" with local balances. Note: the remote balances are included as well for private channels
        total_channel_msat=$(($total_channel_msat + $local_balance_msat))
        if [[ $peer_type == "private" ]]; then total_channel_msat=$(($total_channel_msat + $remote_balance_msat)); fi

        # Tally the balances for global connections
        if [[ $peer_type == "global" ]]; then
            local_total_global_msat=$(($local_total_global_msat + $local_balance_msat))
            remote_total_global_msat=$(($remote_total_global_msat + $remote_balance_msat))
        fi

        # Tally the balances for anonymous connections
        if [[ $peer_type == "anonymous" ]]; then
            local_total_anonymous_msat=$(($local_total_anonymous_msat + $local_balance_msat))
            remote_total_anonymous_msat=$(($remote_total_anonymous_msat + $remote_balance_msat))
        fi

        # Tally local fees required to close each channel (i.e. put them on-chain)
        total_closing_fees_msat=$(($total_closing_fees_msat + $local_closing_fees_msat))

        # Show channel report
        echo "Remote's Alias | Color | Type:    $alias | $color | $peer_type"
        echo "Remote's ID:                      $peer_id"
        echo "Channel (Short) ID:               $channel_id ($short_channel_id)"
        echo "Funded (Local | Remote):          $($0 --msats $local_funds_msat) | $($0 --msats $remote_funds_msat)"
        echo "Local Fees (Base | Percent):      $($0 --msats $local_fee_base_msat) | $(printf "%.4f" $(awk "BEGIN {print $local_fee_proportional_millionths / 10000}")) %"
        echo "Remote Fees (Base | Percent):     $($0 --msats $remote_fee_base_msat) | $(printf "%.4f" $(awk "BEGIN {print $remote_fee_proportional_millionths / 10000}")) %"
        echo "Req. Reserve (Local | Remote):    $($0 --msats $our_reserve_msat) | $($0 --msats $their_reserve_msat)"
        echo "Balance (Local | Remote):         $($0 --msats $local_balance_msat) | $($0 --msats $remote_balance_msat)              $($0 --ratio $local_balance_msat $remote_balance_msat)"
        echo "Spendable (Local | Remote):       $($0 --msats $spendable_msat) | $($0 --msats $receivable_msat) (Balance - \"Req. Reserve\" - \"Estimated On Chain Closing Fee [If We Opened The Channel]\")"
        echo "Closing Fees (Local | Remote):    $($0 --msats $local_closing_fees_msat) | $($0 --msats $remote_closing_fees_msat)"
        echo "Additional Information:           Connected | Who Opened | Private | Last Stable Connection | State"
        echo -n "                                  "
        printf "%-10s  " "$peer_connected"; printf "%-11s  " "$opener"; printf "%-8s  " "$private"; printf "%-23s  " "$last_stable_connection"; echo "$state"

        echo ""
    done <<< "$channels"

    # Report (non-balance) information about this node
    this_node_info=$($LNCLI getinfo)
    this_id=$(echo $this_node_info | jq -r .id)
    this_alias=$(echo $this_node_info | jq -r .alias)
    this_color=$(echo $this_node_info | jq -r .color)
    num_peers=$(echo $this_node_info | jq -r .num_peers)
    num_pending_channels=$(echo $this_node_info | jq -r .num_pending_channels)
    num_active_channels=$(echo $this_node_info | jq -r .num_active_channels)
    num_inactive_channels=$(echo $this_node_info | jq -r .num_inactive_channels)
    fees_collected_msat=$(echo $this_node_info | jq -r .fees_collected_msat)
    our_features_node=$(echo $this_node_info | jq -r .our_features.node)

    echo "################ This Node's Information ################"
    echo "This Node's Alias (Color):        $this_alias ($this_color)"
    echo "This Node's ID:                   $this_id"
    echo "Peer Count:                       $num_peers"
    echo "Fees collected:                   $($0 --msats $fees_collected_msat)"
    echo "Channel Information:              $num_pending_channels | $num_active_channels | $((num_inactive_channels - closed_channels)) | $closed_channels    (Pending | Active | Inactive | Closed)"
    echo "Features:                         $our_features_node"
    echo ""

    # Report all the balances
    echo "####################### Balances ########################"
    echo "On-Chain Balance (Safty Reserve): $($0 --msats $($LNCLI bkpr-listbalances | jq .accounts[0].balances[0].balance_msat))    ($($0 --msats $(grep -m 1 "min-emergency-msat" "/etc/lightningd.conf" | cut -d "=" -f 2)))"
    echo "Total Amount in Channels:         $($0 --msats $total_channel_msat) (Includes the private remote balances)"
    echo "Global Liquidity (Local|Remote):  $($0 --msats $local_total_global_msat) | $($0 --msats $remote_total_global_msat)              $($0 --ratio $local_total_global_msat $remote_total_global_msat)"
    echo "Anonymous Liquidity (Locl|Remte): $($0 --msats $local_total_anonymous_msat) | $($0 --msats $remote_total_anonymous_msat)              $($0 --ratio $local_total_anonymous_msat $remote_total_anonymous_msat)"
    echo "Our Total Closing Fees:           $($0 --msats $total_closing_fees_msat)"

#### What are some analytics of interest here?????????????? Do we create it's own???? Do we create one that shows various transactions????  I think we do.

### There's got to be a quicker way to process jq queries....

#### Work in filters <<<<<<<<<<<<< work in progress
#         global         # Show OUTGOING global channels
#         trusted-p2p    # Show trusted p2p OUTGOING & INCOMING channels
#         private        # Show private OUTGOING channels
#        anonymous      # Show anonymous INCOMING channels
#        $NODE_ID       # Show the channels for a specific node
#        closed         # Show the closed (ONCHAIN) channels




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

elif [[ $1 == "--ratio" ]]; then # Create a visual representation of the local vs remote balance: $LOCAL_BALANCE  $REMOTE_BALANCE
    LOCAL_BALANCE=$2; REMOTE_BALANCE=$3

    # Input checking
    if [[ -z $LOCAL_BALANCE || -z $REMOTE_BALANCE ]]; then
        echo ""; echo "Error! Not all variables (LOCAL_BALANCE & REMOTE_BALANCE) have proper assignments"
        exit 1
    fi

    # Total length of the progress bar
    total_length=50

    # Exit to avoid dividing by 0
    if (( LOCAL_BALANCE + REMOTE_BALANCE == 0 )); then
        echo "| CAN'T DIVIDE BY ZERO |"
        exit 0
    fi

    # Calculate the percentage as input (between 0 and 100)
    percent=$((LOCAL_BALANCE * 100 / (LOCAL_BALANCE + REMOTE_BALANCE)))

    # Validate that the percentage is between 0 and 100
    if (( percent < 0 || percent > 100 )); then
        echo "Invalid percentage. \$LOCAL_BALANCE and \$REMOTE_BALANCE must both be positive integers."
        exit 1
    fi

    # Calculate the number of 'X' and '-' characters
    filled_length=$(( percent * total_length / 100 ))
    empty_length=$(( total_length - filled_length ))

    # Build the progress bar
    progress_bar="|"
    progress_bar+=$(printf "%-${filled_length}s" "X" | tr ' ' 'X')  # Add 'X' characters
    progress_bar+=$(printf "%-${empty_length}s" "-" | tr ' ' '-')  # Add '-' characters
    progress_bar+="|"

    # Print the progress bar
    echo "$progress_bar"

else
    $0 --help
    echo "Script Version 0.47"
fi