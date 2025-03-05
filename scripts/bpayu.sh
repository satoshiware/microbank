#!/bin/bash

# Make sure we are not running as root, but that we have sudo privileges.
if [ "$(id -u)" = "0" ]; then
   echo "This script must NOT be run as root (or with sudo)!"
   exit 1
elif [ "$(sudo -l | grep '(ALL : ALL) ALL' | wc -l)" = 0 ]; then
   echo "You do not have enough sudo privileges!"
   exit 1
fi

# See which bpayu parameter was passed and execute accordingly
if [[ $1 = "--help" ]]; then # Show all possible paramters
    cat << EOF

Future Improvements (i.e. todos):
    Watchtowers are automatically integrated with all trusted (peer bank) channel partners.
        The Eye of Satoshi (rust-teos) Watchtower: https://github.com/talaia-labs/rust-teos
        Watchtower Client: https://github.com/talaia-labs/rust-teos
    Convert all private channels to hosted private channels when the Core Lightning software has advanced sufficiently.
    Remove the bitcoind install from this VM Instance (there may be a plugin for this)
        Note: The current Core Lightning software (2/18/25) requires a local bitcoind instance running for bitcoin-cli access
        (even though it's still connected to this bank's full bitcoin node). On future updates, it may no longer be necessary.


    Options:
      --help            Display this help message and exit
      --install         Install (or upgrade) this script (bpayu) in /usr/local/sbin (/satoshiware/microbank/scripts/bpayu.sh)
      --generate        (Re)Generate(s) the environment file (w/ needed constants) for this utility in /etc/default/bpayu.env
      --ip_update       For nodes without a static IP (using dynamic DNS), this will update the ip that's announced by the lightning node. !!!!!!!!!! Not done yet !!!!!!!!!!!!!!!!!!!!!!!
      --global_channel  Establish a "global" channel to improve liquidity world-wide (0 reserve): $PEER_ID  $AMOUNT
                            Note: The ID of each global peer is stored in the file /var/log/lightningd/global_peers
      --local_channel   Establish a "local" channel to a "trusted" peer bank (0 reserve): $PEER_ID  $AMOUNT
                            Note: The ID of each local trusted peer is stored in the file /var/log/lightningd/local_peers
      --private_channel Establish a private channel with the BTCPAY server: $PEER_ID  $LOCAL_IP_ADDRESS  $AMOUNT
                            Note: The ID & IP of each BTCPAY server is stored in the file /var/log/lightningd/local_channels
      --update_fees     Change the channel % fee: [$SHORT_CHANNEL_ID | $CHANNEL_ID | $PEER_ID]  $FEE_RATE (e.g. 1000 = 0.1% fee)


Useful Commands:
    lncli getinfo                   # See the info' on this node
    lncli listnodes                     # Show all nodes (and info') on the lightning network
    lncli listnodes $CONNECTION_ID      # Get info' on another node
    lncli listpeers                     # Show all nodes that share a connection with this node
    lncli newaddr                   # Get a deposit address

    bc1qsfw44ge7w7grqn0pzvm8cm39eegfr898kthrdd

################################# Some maybe useful stuff todo ############################################
list peers (and information) without channels
List ALL peers (and information) with channels (I'm still assuming they are always connected) [all all channel information]
List Local (and information) peers [all all channel information]
List Global (and information) peers [all all channel information]
List Unsolicited (and information) peers [all all channel information]  (aka incomming connections)



during the install, create cronjob that sends summery
during the install, create cronjob that checks balances and sends alerts
during the install, create cronjob that tries to balance channels.

What kind of notification do we want?
    A cron job that gives us a summary (balances and analytics)
        there is a bookeeper plugin and a "accounting" plugin or something like that.
    When channel balances become low.
    cron job that tries to balance






#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    lncli updatechanpolicy --base_fee_msat 100 --fee_rate 0.00001 --time_lock_delta 50 --min_htlc_msat 1000 --chan_point 17ec2d0ac18d953b1dfe2cafa116b0c118020cab4d80c4063fe98debda6df469:1

    lncli openchannel --node_key 021c97a90a411ff2b10dc2a8e32de2f29d2fa49d41bfbb52bd416e460db0747d0d --connect 50.112.125.89:9735 --local_amt 210000000 --remote_max_value_in_flight_msat 105000000000 --max_local_csv 50


    Each channel has its own fee policy. Those fee policies include: Base Fee + % Fee
    min_htlc_msat

    The waiting period can be defined individually for each channel at its creation using the --max_local_csv
    --remote_csv_delay flags of lncli openchannel.
    A large waiting period makes it safer to recover from a failure, but will also lock up funds for longer if a channel closes unilaterally.


    How can I put a policy to protect myself?


Initial Goals (Level 1):
    No dual funded or splicing supported yet; Single wallet for balance both on-chain and lighting togethor
    Policy and methods for lightning nodes to connect with this one.
        Minimum Amount: 10,000 SATS (default)
        Maximum Amount: No Maximum
        They Pay the fee
        Can I set the fee
    Channel Observation and management (How to close and open)
    Lightning Address server
    Generate invoice for an arbitrary amount

    Generate invoice for a specific amount
    Generate bolt12 invoice for arbitrary amount that can be paid infinite times.





EOF

elif [[ $1 == "--install" ]]; then # Install (or upgrade) this script (bpayu) in /usr/local/sbin (/satoshiware/microbank/scripts/bpayu.sh)
    echo "Installing this script (bpayu) in /usr/local/sbin/"
    if [ -f /usr/local/sbin/bpayu ]; then
        echo "This script (bpayu) already exists in /usr/local/sbin!"
        read -p "Would you like to upgrade it? (y|n): "
        if [[ "${REPLY}" = "y" || "${REPLY}" = "Y" ]]; then
            sudo rm /usr/local/sbin/bpayu
            cd ~; git clone https://github.com/satoshiware/microbank
            bash ~/microbank/scripts/bpayu.sh --install
            rm -rf microbank
            exit 0
        else
            exit 0
        fi
    fi

    sudo cat $0 | sudo tee /usr/local/sbin/bpayu > /dev/null
    sudo chmod +x /usr/local/sbin/bpayu

elif [[ $1 == "--ip_update" ]]; then # For nodes without a static IP (using dynamic DNS), this will update the ip that's announced by the lightning node.
    echo ""

elif [[ $1 == "--global_channel" ]]; then # Establish a "global" channel to improve liquidity world-wide (0 reserve)
    PEER_ID=$2; AMOUNT=$3

    # Input checking
    if [[ -z $PEER_ID || -z $AMOUNT ]]; then
        echo ""; echo "Error! Not all variables (PEER_ID & AMOUNT) have proper assignments"
        exit 1
    fi

    lncli connect $PEER_ID; sleep 2
    RESULT=$(lncli fundchannel -k id=$PEER_ID amount=$AMOUNT reserve=0)

    echo $RESULT

    # On success, add the PEER_ID to the global_peers file without duplicates
    if [[ $RESULT != *"code"* ]]; then # If no error "code" was thrown then assume success
        if ! sudo grep -Fxq $PEER_ID /var/log/lightningd/global_peers; then
            echo $PEER_ID | sudo -u lightning tee -a /var/log/lightningd/global_peers
        fi
    fi

elif [[ $1 == "--local_channel" ]]; then # Establish a "local" channel to a "trusted" peer bank (0 reserve): $PEER_ID  $AMOUNT
    PEER_ID=$2; AMOUNT=$3

    # Input checking
    if [[ -z $PEER_ID || -z $AMOUNT ]]; then
        echo ""; echo "Error! Not all variables (PEER_ID & AMOUNT) have proper assignments"
        exit 1
    fi

    lncli connect $PEER_ID; sleep 2
    RESULT=$(lncli fundchannel -k id=$PEER_ID amount=$AMOUNT reserve=0)

    echo $RESULT

    # On success, add the PEER_ID to the local_peers file without duplicates
    if [[ $RESULT != *"code"* ]]; then # If no error "code" was thrown then assume success
        if ! sudo grep -Fxq $PEER_ID /var/log/lightningd/local_peers; then
            echo $PEER_ID | sudo -u lightning tee -a /var/log/lightningd/local_peers
        fi
    fi

elif [[ $1 == "--btcpay" ]]; then # Establish a private channel with the BTCPAY server: $PEER_ID  $LOCAL_IP_ADDRESS  $AMOUNT
    PEER_ID=$2; LOCAL_IP_ADDRESS=$3; AMOUNT=$4

    # Input checking
    if [[ -z $PEER_ID || -z $LOCAL_IP_ADDRESS || -z $AMOUNT ]]; then
        echo ""; echo "Error! Not all variables (PEER_ID, LOCAL_IP_ADDRESS, & AMOUNT) have proper assignments"
        exit 1
    fi

    lncli connect $PEER_ID $LOCAL_IP_ADDRESS; sleep 2
    RESULT=$(lncli fundchannel -k id=$PEER_ID amount=$AMOUNT reserve=0 announce=false)

    echo $RESULT

    # On success, add the PEER_ID to the btcpay file without duplicates
    if [[ $RESULT != *"code"* ]]; then # If no error "code" was thrown then assume success
        if ! sudo grep -Fxq "$PEER_ID $LOCAL_IP_ADDRESS" /var/log/lightningd/btcpay; then
            echo "$PEER_ID $LOCAL_IP_ADDRESS" | sudo -u lightning tee -a /var/log/lightningd/btcpay
        fi
    fi

elif [[ $1 == "--update_fees" ]]; then # Change the fee of a channel
    PEER_SHORT_CHANNEL_ID=$2 # This parameter contains the "Short Channel ID", Channel ID, or Peer ID (all channels with this given peer).
    FEE_RATE=$3 # Fee added proportionally (per-millionths) to any routed payment volume (e.g. 1000 = 0.1% fee).

    # Input checking
    if [[ -z $PEER_CHANNEL_ID || $FEE_RATE ]]; then
        echo ""; echo "Error! Insufficient parameters passed to this routine!"
        exit 1
    fi

    lncli setchannel -k id=$PEER_SHORT_CHANNEL_ID feeppm=$FEE_RATE

else
    $0 --help
    echo "Script Version 0.01"
fi