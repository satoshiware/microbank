#!/bin/bash

# Make sure we are not running as root, but that we have sudo privileges.
if [ "$(id -u)" = "0" ]; then
   echo "This script must NOT be run as root (or with sudo)!"
   exit 1
elif [ "$(sudo -l | grep '(ALL : ALL) ALL' | wc -l)" = 0 ]; then
   echo "You do not have enough sudo privileges!"
   exit 1
fi

# See which litu parameter was passed and execute accordingly
if [[ $1 = "--help" ]]; then # Show all possible paramters
    cat << EOF
    Options:
      --help            Display this help message and exit
      --install         Install (or upgrade) this script (litu) in /usr/local/sbin (/satoshiware/microbank/scripts/litu.sh)
      --ip_update       For nodes without a static IP (using dynamic DNS), this will update the ip that's announced by the lightning node. !!!!!!!!!! Not done yet !!!!!!!!!!!!!!!!!!!!!!!
      --global_channel  Establish a "global" channel to improve liquidity world-wide (0 reserve): $PEER_ID  $AMOUNT
                            Note: The ID of each global peer is stored in the file /var/log/lightningd/global_peers
      --local_channel  Establish a "local" channel to a "trusted" peer bank (0 reserve): $PEER_ID  $AMOUNT
                            Note: The ID of each local trusted peer is stored in the file /var/log/lightningd/local_peers
      --update_fees     Change the channel % fee: [$SHORT_CHANNEL_ID | $CHANNEL_ID | $PEER_ID]  $FEE_RATE (e.g. 1000 = 0.1% fee)


Useful Commands:
	lncli getinfo 					# See the info' on this node
	lncli listnodes 					# Show all nodes (and info') on the lightning network
	lncli listnodes $CONNECTION_ID  	# Get info' on another node
	lncli listpeers 					# Show all nodes that share a connection with this node
	
	
################################# Some maybe useful stuff todo ############################################
list peers (and information) without channels
List ALL peers (and information) with channels (I'm still assuming they are always connected) [all all channel information]
List Local (and information) peers [all all channel information]
List Global (and information) peers [all all channel information]
List Unsolicited (and information) peers [all all channel information]  (aka incomming connections)



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