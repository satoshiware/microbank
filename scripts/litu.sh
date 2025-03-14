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
      --install         Install (or upgrade) this script (litu) in /usr/local/sbin (/satoshiware/microbank/scripts/litu.sh)
      --generate        (Re)Generate(s) the environment file (w/ needed constants) for this utility in /etc/default/litu.env <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
      --ip_update       For nodes without a static IP (using dynamic DNS), this will update the ip that's announced by the lightning node. !!!!!!!!!! Not done yet !!!!!!!!!!!!!!!!!!!!!!!
      --global_channel  Establish a "global" channel to improve liquidity world-wide (w/ 0 reserves): \$PEER_ID  \$AMOUNT_SATS (Note: min-emergency-msat is set to 0.00100000000_000)
      --peer_channel    Establish a "peer" channel to a "trusted" local bank (w/ 0 reserves): \$PEER_ID  \$AMOUNT_SATS (Note: min-emergency-msat is set to 0.00100000_000)
      --private_channel Establish a "private" channel with an internal Core Lightning node: \$PEER_ID \$LOCAL_IP_ADDRESS \$AMOUNT_SATS \$ALIAS \$COLOR (Note: min-emergency-msat is set to 0.00100000_000)
      --update_fees     Change the channel % fee: [\$SHORT_CHANNEL_ID | \$CHANNEL_ID | \$PEER_ID]  \$FEE_RATE (e.g. 1000 = 0.1% fee)
      --summary         Produce summaries of peer nodes, channels, this node, and balances: \$FILTER (optional)
      --commands        List of some of Core Lightning CMDs that may be of interest
      --msats           Convert a figure in mSATS and display it in the form of BTC.SATS_mSATS: \$AMOUNT_MSATS
      --ratio           Create a visual representation of the local vs remote balance: \$LOCAL_BALANCE  \$REMOTE_BALANCE
      --clean           Cleanup (delete) forwards, pays, and invoices that are more than two days old
      --empty           Empties (sends) all the spendable msats over a private channel. Routine only works on private lightning nodes /w a single channel
      --path            Find the shortest path & fee to send a given amount: (\$PEER_ID|\$INVOICE|\$OFFER|\$REQUEST) <\$AMOUNT_MSATS=1000>
      --loop            Route SATS through two channels connected to this node (1 in and 1 out): \$START_SHORT_CHANNEL  \$END_SHORT_CHANNEL  \$AMOUNT_MSATS  <\$SEND_NOW=false>

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

    # Make sure the node id files exist to distinguish the different types of peers and the channels we share
    sudo -u lightning touch /var/log/lightningd/global_channels
    sudo -u lightning touch /var/log/lightningd/peer_channels
    sudo -u lightning touch /var/log/lightningd/private_channels

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

elif [[ $1 == "--update_fees" ]]; then # Change the fee of a channel
    PEER_SHORT_CHANNEL_ID=$2 # This parameter contains the "Short Channel ID", Channel ID, or Peer ID (all channels with this given peer).
    FEE_RATE=$3 # Fee added proportionally (per-millionths) to any routed payment volume (e.g. 1000 = 0.1% fee).

    # Input checking
    if [[ -z $PEER_CHANNEL_ID || -z $FEE_RATE ]]; then
        echo ""; echo "Error! Insufficient parameters passed to this routine!"
        exit 1
    fi

    $LNCLI setchannel -k id=$PEER_SHORT_CHANNEL_ID feeppm=$FEE_RATE

elif [[ $1 == "--summary" ]]; then # Produce summaries of peer nodes, channels, this node, and balances: \$FILTER (optional)
    FILTER=$2

    echo ""; echo "####################### Channels ########################"
    total_channel_msat=0
    closed_channels=0 # Running tally of all the closed channels so far
    local_total_global_msat=0 # Running tally of all the balances on the local side for global connections
    remote_total_global_msat=0 # Running tally of all the balances on the remote side for global connections
    local_total_anonymous_msat=0 # Running tally of all the balances on the local side for anonymous connections
    remote_total_anonymous_msat=0 # Running tally of all the balances on the remote side for anonymous connections
    total_closing_fees_msat=0 # Running tally of all the local fees required to close all the channels (i.e. put them on-chain)
    NODE_ID=""; if [[ $FILTER =~ ^[a-f0-9]{66}$ ]]; then NODE_ID=$FILTER; fi # Check to see if the filter contains a 66 digit (lower case) node id number
    channels=$($LNCLI listpeerchannels $NODE_ID | jq -c '.channels[]')
    while IFS= read -r channel; do # Loop through the channels and process them
        state=$(echo "$channel" | jq -r .state)

        # Filter where only closed (non-deleted) channels are shown
        if [[ $state == "ONCHAIN" ]]; then
            ((closed_channels++))
            if [[ ! $FILTER == "closed" ]]; then # If this channel is closed (ONCHAIN) without the "closed" filter then skip
                continue
            fi
        else
            if [[ $FILTER == "closed" ]]; then # If this channel is NOT closed (ONCHAIN), but has the "closed" filter turned on then skip
                continue
            fi
        fi

        peer_id=$(echo "$channel" | jq -r .peer_id)
        if grep -q $peer_id "/var/log/lightningd/global_channels"; then peer_type="global"
        elif grep -q $peer_id "/var/log/lightningd/peer_channels"; then peer_type="trusted-p2p"
        elif grep -q $peer_id "/var/log/lightningd/private_channels"; then  peer_type="private"
        else peer_type="anonymous"; fi

        # Execute private, global, trusted-p2p, and anonymous filters
        if [[ $FILTER == "private" || $FILTER == "global" || $FILTER == "trusted-p2p" || $FILTER == "anonymous" ]]; then
            if ! [[ $peer_type == $FILTER ]]; then continue; fi
        fi

        # Collect data for this channel
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

    # If a filter is enabled then exit
    if [[ $FILTER == "private" || $FILTER == "global" || $FILTER == "trusted-p2p" || $FILTER == "anonymous" || $FILTER == "closed" || ! -z $NODE_ID ]]; then exit 0; fi

    # Show file location used to distinguish different peers
    echo "File Locations for the three different types of NODE IDs:"
    echo "    GLOBAL:       /var/log/lightningd/global_channels"
    echo "    TRUSTED-P2P:  /var/log/lightningd/peer_channels"
    echo "    PRIVATE:      /var/log/lightningd/private_channels"
    echo ""

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
    echo ""

    # Show Filters
    echo "####################### Filters ########################"
    echo "Enter one of the following filters in the command line (e.g. \"lncli --summary global\"):"
    echo "    global         # Show OUTGOING GLOBAL channels"
    echo "    trusted-p2p    # Show TRUSTED P2P OUTGOING & INCOMING channels"
    echo "    private        # Show PRIVATE OUTGOING channels"
    echo "    anonymous      # Show ANONYMOUS INCOMING channels"
    echo "    \$NODE_ID       # Show the channels for a specific \$NODE_ID"
    echo "    closed         # Show the closed (ONCHAIN) channels"
    echo ""

elif [[ $1 == "--commands" ]]; then # List of some of Core Lightning CMDs that may be of interest
    cat << EOF
    REMEMBER: Type "lncli" before each of these commands

    [basic]
    getinfo                         # See the info' on this node
    listfunds                       # Displays all funds available, either in unspent outputs (UTXOs) or funds locked in currently open channels
    listnodes PEER_ID               # Get info' on another (non-private) node
    listpeers                       # Show all nodes that share a connection with this node
    listforwards (settled|offered)  # Displays all forwarded htlcs that have been settled or are currently offered

    [clean-up]
    autoclean-once <SUBSYSTEM> 3600 # Do a single sweep to delete (3600 Sec.)old entries. [SUBSYSTEM = succeededforwards | failedforwards | succeededpays | failedpays | paidinvoices | expiredinvoices]
    autoclean-status                # Tells you about the status of the autoclean plugin
    delforward CH_ID HTL_ID STATUS  # Delete a forward
    delpay PAYMENT_HASH STATUS      # Deletes a payment with the given PAYMENT_HASH
    delinvoice LABEL STATUS         # Removes an invoice with STATUS as given in listinvoices

    [on-chain wallet]
    newaddr                         # Generates a new address which can subsequently be used to fund channels managed by the Core Lightning node
    listaddresses                   # List of all Bitcoin addresses that have been generated and issued by the Core Lightning node up to the current date
    listtransactions                # Returns transactions tracked in the wallet. This includes deposits, withdrawals and transactions related to channels
    withdraw ADDRESS AMOUNT         # Send funds from Core Lightning's internal on-chain wallet to a given \$ADDRESS.
                                    # The \$AMOUNT (msat, sats [default], btc, or "all") to be withdrawn from the internal on-chain wallet.
                                    # When using "all" for the \$AMOUNT, it will leave the at least min-emergency-msat as change if there are any open (or unsettled) channels.
    [channels]
    listpeerchannels                # Return a list of this node's channels
    listpeerchannels PEER_ID        # Filter the list of this node's channels by a connected node's id
    close ID                        # Attempts to close the channel cooperatively or unilaterally after unilateraltimeout (default: 48 hours) [\$ID = \$SHORT_CHANNEL_ID | \$CHANNEL_ID | \$PEER_ID]
    listhtlcs CHANNEL_ID            # List all HTLCs that have ever appeared on a given channel

    [bookkeeper]
    bkpr-listbalances               # List of all current and historical account balances both on-chain and channel balances
    bkpr-channelsapy START END      # lists stats on routing income, leasing income, and various calculated APYs for channel routed funds in a given time frame (UNIX Time Stamps)
    bkpr-dumpincomecsv quickbooks /var/lib/lightningd/bitcoin true START END    # Create a csv file in a given time frame (UNIX Time Stamps)
    bkpr-listincome true START END  # list of all income impacting events recorded for this node in a given time frame (UNIX Time Stamps)

    [payments]
    pay <BOLT_INVOICE>              # Pay a bolt invoice where the amount is embedded inside the invoice
    pay <BOLT_INVOICE AMOUNT>       # Pay a bolt "any" invoice with an arbitrary amount
    listpays null null complete     # Shows the status of all pay commands completed successfully from this node
    keysend PEER_ID AMOUNT          # Send the specified AMOUNT (msats) without an invoice (as a consequence, there is not proof-of-payment) to a given PEER_ID

    [invoices]
    listinvoices                    # List all invoices ever created on this node
    invoice <AMOUNT LABEL DESCR.>   # Creates an invoice that will be paid to this node. The Amount can be any value (msats) or the keyword "any"


    getroute PEER_ID AMOUNT 0       # Attempts to find the best route for the payment of AMOUNT (msats) to lightning node PEER_ID with a risk factor of 0
    decode <INVOICE????OR SOMETHING>                            # Checks and parses (decodes) invoices, offers, invoice requests, and other formats


????????????????????????????????????????????????????????????????????????????????????????????????????


    [offers]
    offer <AMOUNT DESCRIPTION>      # Create an offer. The Amount can be any value (msats) or the keyword "any"
    listoffers null true            # List all active offers, or replace "null" with <OFFER_ID>, only the offer with that OFFER_ID (if it exists)
    enableoffer <OFFER_ID>          # Enables an offer, after it has been disabled
    disableoffer <OFFER_ID>         # Disables an offer, so that no further invoices will be given out.

    [invoice_requests]
    invoicerequest



EOF

elif [[ $1 == "--msats" ]]; then # Convert a figure in mSATS and display it in the form of BTC.SATS_mSATS: $AMOUNT_MSATS
    AMOUNT_MSATS=$2

    # Input checking
    if [[ -z $AMOUNT_MSATS ]]; then
        echo ""; echo "Error! There needs to be a parameter passed to this routine!"
        exit 1
    fi

    # Format result to have exactly 11 digits after the decimal
    formatted_result=$(echo $AMOUNT_MSATS | awk '{printf "%.11f\n", $1 / 100000000000}')

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

elif [[ $1 == "--clean" ]]; then # Cleanup (delete) forwards, pays, and invoices that are more than two days old
    $LNCLI autoclean-once succeededforwards 172800
    $LNCLI autoclean-once failedforwards 172800
    $LNCLI autoclean-once succeededpays 172800
    $LNCLI autoclean-once failedpays 172800
    $LNCLI autoclean-once paidinvoices 172800
    $LNCLI autoclean-once expiredinvoices 172800

elif [[ $1 == "--empty" ]]; then # Empties (sends) all the spendable msats over a private channel. Routine only works on private lightning nodes /w a single channel
    # Example, Empty an amount from my private node:
    if [[ $($LNCLI listpeerchannels | jq '.channels | length') -eq 1 ]]; then # Verify that it only has 1 channel open
        peer_id=$($LNCLI listpeerchannels | jq -r .channels[0].peer_id)
        if grep -q $peer_id "/var/log/lightningd/private_channels"; then
            spendable_msat=$($LNCLI listpeerchannels | jq -r .channels[0].spendable_msat)
            spendable_msat=$((spendable_msat-1)) # Deduct 1 msat in order for it to send the maximum amount (bug workaround I guess)
            $LNCLI keysend $peer_id $spendable_msat
        else
            echo "Error! This routine is for private lightning nodes only!"
            echo "The node, where you are sending all your sats, must be owned by you with its peer_id appearing in the file /var/log/lightningd/private_channels"
        fi
    else
        echo "Error! Is there more than 1 channel?!"
        echo "This routine is for private lightning nodes only with a single channel"
    fi

elif [[ $1 == "--path" ]]; then # Find the shortest path & fee to send a given amount: ($PEER_ID|$INVOICE|$OFFER|$REQUEST) <$AMOUNT_MSATS=1000>
    ID_INV_OFFR_REQ=$2; AMOUNT=$3

    # Input checking
    if [[ -z $ID_INV_OFFR_REQ ]]; then
        echo ""; echo "Error! Not all variable (ID_INV_OFFR_REQ) does not have a proper assignment!"
        exit 1
    fi

    # Get and show this node's ID
    THIS_NODE_ID=$($LNCLI getinfo | jq -r .id)
    echo ""; echo "##### THIS NODE'S ID: $THIS_NODE_ID"

    # Get the NODE_ID of the payee
    if [[ $ID_INV_OFFR_REQ =~ ^[a-f0-9]{66}$ ]]; then # Is the passed parameter already a NODE_ID
        NODE_ID=$ID_INV_OFFR_REQ
        echo ""; echo "##### REMOTE NODE ID: $NODE_ID"
    else
        DECODED=$($LNCLI decode $ID_INV_OFFR_REQ)
        echo ""; echo "##### DECODED (PEER_ID|INVOICE|OFFER|REQUEST) #####"; echo $DECODED | jq

        payee=$(echo $DECODED | jq -r .payee)
        offer_issuer_id=$(echo $DECODED | jq -r .offer_issuer_id)
        invreq_payer_id=$(echo $DECODED | jq -r .invreq_payer_id)
        if [[ $payee =~ ^[a-f0-9]{66}$ ]]; then # Is the passed parameter a lightning invoice
            NODE_ID=$payee
            if [[ -z $AMOUNT ]]; then
                AMOUNT=$($LNCLI decode $ID_INV_OFFR_REQ | jq -r .amount_msat)
            fi
        elif [[ $offer_issuer_id =~ ^[a-f0-9]{66}$ ]]; then # Is the passed parameter a lightning offer
            NODE_ID=$offer_issuer_id
            if [[ -z $AMOUNT ]]; then
                AMOUNT=$($LNCLI decode $ID_INV_OFFR_REQ | jq -r .offer_amount_msat)
            fi
        elif [[ $invreq_payer_id =~ ^[a-f0-9]{66}$ ]]; then # Is the passed parameter a lightning invoice request
            NODE_ID=$invreq_payer_id
            if [[ -z $AMOUNT ]]; then
                AMOUNT=$($LNCLI decode $ID_INV_OFFR_REQ | jq -r .invreq_amount_msat)
            fi
        else
            echo ""; echo "Error! The passed parameter is not a NODE_ID, INVOICE, OFFER, or INVOICE REQUEST!"
            exit 1
        fi
    fi

    # If non-existent or less than 1000 mSATS (1 SAT) then set AMOUNT to 1000 mSATS (1 SAT)
    if [[ -z $AMOUNT || $AMOUNT -lt 1000 ]]; then AMOUNT=1000; fi

    # Find and show the best route to SEND
    routes=$($LNCLI getroute $NODE_ID $AMOUNT 0)
    echo ""; echo "##### Shortest SEND Route For $($0 --msats $AMOUNT) BTC.SATS_mSATS #####"; echo $routes | jq; echo ""

    # Show the final FEE to SEND that would be paid
    amount_sent=$(echo $routes | jq .route[0].amount_msat) # The amount in the first element
    amount_received=$(echo $routes | jq -r '.route[-1]' | jq .amount_msat) # The amount in the last element
    echo "Send Fee Required: $($0 --msats $((amount_sent - amount_received)))"

    # Find and show the best route to RECEIVE
    routes=$($LNCLI getroute $THIS_NODE_ID $AMOUNT 0 null $NODE_ID)
    echo ""; echo "##### Shortest RECEIVE Route For $($0 --msats $AMOUNT) BTC.SATS_mSATS #####"; echo $routes | jq; echo ""

    # Show the final FEE the sender would pay (RECEIVE)
    amount_sent=$(echo $routes | jq .route[0].amount_msat) # The amount in the first element
    amount_received=$(echo $routes | jq -r '.route[-1]' | jq .amount_msat) # The amount in the last element
    echo "SENDER's Fee Required: $($0 --msats $((amount_sent - amount_received)))"; echo ""

elif [[ $1 == "--loop" ]]; then # Route SATS through two channels connected to this node (1 in and 1 out): \$START_SHORT_CHANNEL  \$END_SHORT_CHANNEL  \$AMOUNT_MSATS  <\$SEND_NOW=false>
    START_SHORT_CHANNEL=$2; END_SHORT_CHANNEL=$3; AMOUNT=$4; SEND_NOW=$5

    # Input checking
    if [[ -z $START_SHORT_CHANNEL || -z $END_SHORT_CHANNEL || -z $AMOUNT ]]; then
        echo ""; echo "Error! Not all variables (START_CHANNEL, END_CHANNEL, and/or AMOUNT) have a proper assignments!"
        exit 1
    fi

    # Make sure AMOUNT is a number and greater than 1000 mSATS
    if [[ ! $AMOUNT =~ ^-?[0-9]+$ || $AMOUNT -lt 1000 ]]; then
        echo "Error! \$AMOUNT must be an integer (msats) greater than 1000 mSATS!"
        exit 1
    fi

    # Get and show this node's ID
    this_node_id=$($LNCLI getinfo | jq -r .id)

    # Get the START_NODE_ID, END_NODE_ID, spendable, receivable, and an array of all the active channels (except START_NODE_ID)
    channels_array="[" # Add a start bracket for the array
    channels=$($LNCLI listpeerchannels | jq -c '.channels[]')
    while IFS= read -r channel; do # Loop through the channels and process them
        state=$(echo "$channel" | jq -r .state)

        short_channel_id=$(echo "$channel" | jq -r .short_channel_id)
        if [[ $short_channel_id == "$START_SHORT_CHANNEL" ]]; then # Get the first node on the payment route
            if [[ ! $state == "CHANNELD_NORMAL" ]]; then echo "Error! Start channel is not active!"; fi
            start_node_id=$(echo "$channel" | jq -r .peer_id)
            spendable_msat=$(echo "$channel" | jq -r .spendable_msat)
        else
            # Get the last node before this one on the payment route
            if [[ $short_channel_id == "$END_SHORT_CHANNEL" ]]; then
                if [[ ! $state == "CHANNELD_NORMAL" ]]; then echo "Error! End channel is not active!"; fi
                end_node_id=$(echo "$channel" | jq -r .peer_id)
                receivable_msat=$(echo "$channel" | jq -r .receivable_msat)
            fi

            # Build an array of all the active channels except the $START_SHORT_CHANNEL
            if [[ $state == "CHANNELD_NORMAL" ]]; then
                channels_array="$channels_array$short_channel_id/$(echo "$channel" | jq -r .direction),"
            fi
        fi
    done <<< "$channels"
    channels_array="${channels_array%?}]" # Remove the last comma and add an end cap ']' for the array

    # Make sure the channels (connected to this node) can handle the full $AMOUNT transferred
    if [[ $AMOUNT -gt $(( $receivable_msat - 1 )) || $AMOUNT -gt $(( $spendable_msat - 1)) ]]; then # Possible bug... doesn't send unless it is 1 mSAT under
        echo "Error! Cannot send that many mSATS!"
        exit 1
    fi

    # Calculate the route for this loop and the total fee to transfer the desired amount
    route=$($LNCLI getroute -k "id"="$end_node_id" "amount_msat"=$AMOUNT "riskfactor"=0 "exclude"=$channels_array)
    final_hop_amount=$(echo $route | jq .route[-1].amount_msat)
    route=$(echo $route | jq .route | tr -d '[:space:]') # Remove "route" structure from the json data and remove all spaces
    route="${route%?}" # Remove the ending bracket
    last_hop=$($LNCLI getroute -k "id"="$this_node_id" "amount_msat"=$final_hop_amount "riskfactor"=0 "fromid"="$end_node_id" | jq .route[] | tr -d '[:space:]')]
    total_fee=$(( $AMOUNT - $(echo ${last_hop%?} | jq .amount_msat) )) # Calculate the total fee
    route="$route,$last_hop" # Add the route with the last hop seperated by a comma

    # Create an invoice with "any" amount that will be used to receive the funds back in the end channel
    invoice=$($LNCLI invoice any "loop $(date +%s)" "Send $AMOUNT msats in a loop: START_SHORT_CHANNEL=$start_node_id, END_SHORT_CHANNEL=$end_node_id")
    payment_hash=$(echo $invoice | jq .payment_hash)
    payment_secret=$(echo $invoice | jq .payment_secret)

    # Print Summary
    echo ""; echo "Summary:"
    echo "    This Node's ID:       $this_node_id"
    echo "    Amount:               $($0 --msats $AMOUNT)"
    echo "    Total Fee:            $($0 --msats $total_fee)"
    echo "    Start Node Alias:     $($LNCLI listnodes $start_node_id | jq -r .nodes[0].alias)"
    echo "    Start Node ID:        $start_node_id"
    echo "    Start Node Channel:   $START_SHORT_CHANNEL"
    echo "    Sendable (mSATS):     $($0 --msats $spendable_msat)"
    echo "    End Node Alias:       $($LNCLI listnodes $end_node_id | jq -r .nodes[0].alias)"
    echo "    End Node ID:          $end_node_id"
    echo "    End Node Channel:     $END_SHORT_CHANNEL"
    echo "    Receivable (mSATS):   $($0 --msats $receivable_msat)"
    echo "    Excluded Channels:    $channels_array"

    # Print Invoice
    echo ""; echo "Invoice:"
    echo $invoice

    # Print Route
    echo ""; echo "Route:"
    echo $route | jq

    # Print Aliases
    echo ""; echo "Alias:"
    nodes=$($LNCLI listpeerchannels | jq -c '.[]')
    while IFS= read -r node; do # Loop through the channels and process them
        echo "    $($LNCLI listnodes $(echo $node | jq -r .id) | jq -r .nodes[0].alias)"
    done <<< "$nodes"

    # If SEND_NOW is not equal to true ask user if they want to send
    if [[ ! $SEND_NOW == "true" ]]; then
        read -p "Do you want to continue with the transfer? (yes/no): " user_input
        if ! [[ "$user_input" == "yes" || "$user_input" == "y" ]]; then exit 1; fi
    fi

    # Make the transfer
    lncli sendpay -k "route"=$route "payment_hash"=$payment_hash "payment_secret"=$payment_secret

else
    $0 --help
    echo "Script Version 1.01"
fi