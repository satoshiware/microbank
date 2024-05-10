This is a list of scripts that are used to install and setup a "micronode" cluster.
What is a micronode cluster?
Basically, it's a few nodes, each with a specific task, with the bitcoin core installed and running a microcurrency.

To execute any of these scripts, login as a sudo user (that is not root) and execute the following commands (substituting the $SCRIPT NAME variable accordingly):
    sudo apt-get -y install git
    cd ~; git clone https://github.com/satoshiware/microbank
    bash ./microbank/scripts/pre_fork_micro/$SCRIPT_NAME.sh
    rm -rf microbank
	
# cross-compile_micro.sh
This file generates the binanries (and sha 256 checksums) for bitcoin core (microcurrency edition)
from the https://github.com/satoshiware/bitcoin repository. This script was made for linux
x86 64 bit and has been tested on Debian 11/12 (w/ WSL).
Compilation Supported Processors:
	x86 64 bit (x86_64)
	ARM 64 bit (aarch64-linux-gnu)

# p2p_node.sh
This script installs a "p2p" micronode (within a cluster) which is used to manage connections with all other internal and external nodes.

To run this script, you'll need the Bitcoin Core micronode download URL (tar.gz file) with its SHA 256 Checksum to continue.

Recommended Hardware:
    Rasperry Pi Compute Module 4: CM4004000 (w/ Compute Blade)
    4GB RAM
    M.2 PCI SSD 500MB
    Netgear 5 Port Switch (PoE+ @ 120W)
	
Utility script(s) installed:
	p2pconnect.sh

# wallet_node.sh
The "wallet_node.sh" script installs a "wallet" micronode (within a cluster).
The Wallet node is used to manage the banks microcurrency hotwallet and the payouts for mining contracts.

To run this script, you'll need the Bitcoin Core micronode download URL (tar.gz file) with its SHA 256 Checksum to continue.
Also, you will need to plug in a USB drive that will be used to backup the "bank" and "mining" wallets along with the "passphrase"
    STORE IN SAFE & SECURE PLACE WHEN FINISHED!!!

Recommended Hardware:
    Rasperry Pi Compute Module 4: CM4004000 (w/ Compute Blade)
    4GB RAM
    M.2 PCI SSD 500MB
    Netgear 5 Port Switch (PoE+ @ 120W)
	** USB Drive **
	
Utility script(s) installed:
	mnconnect.sh
	teller.sh
	payouts.sh

# stratum_node.sh
This script installs a "stratum" micronode (within a cluster).
The Stratum node is used to manage the microcurrency mining operation for a "minibank".

To run this script, you'll need the Bitcoin Core micronode download URL (tar.gz file) with its SHA 256 Checksum to continue.
Also, you will need to plug in the USB drive that contains the encrypted mining wallet that was generated from the wallet install.

Recommended Hardware:
    Rasperry Pi Compute Module 4: CM4004000 (w/ Compute Blade)
    4GB RAM
    M.2 PCI SSD 500MB
    Netgear 5 Port Switch (PoE+ @ 120W)
	
	**USB from the wallet creation

Utility script(s) installed:
	mnconnect.sh
	stmutility.sh
	
# electrs_node.sh ######## Still under active development: Add electrs (Rust) https://github.com/romanz/electrs, update readme information and comments ########
This script installs a "electrs" micronode (within a cluster).
The electrs server indexes the entire Bitcoin blockchain, and the resulting index enables fast queries for any given user wallet,
allowing the user to keep real-time track of balances and transaction history.
To run this script, you'll need the Bitcoin Core micronode download URL (tar.gz file) with its SHA 256 Checksum and
you'll also need the electrs binaries (tar.gz file) with its SHA 256 Checksum to continue.

Recommended Hardware:
    Rasperry Pi Compute Module 4: CM4008000 (w/ Compute Blade)
    8GB RAM
    M.2 PCI SSD 1TB
    Netgear 5 Port Switch (PoE+ @ 120W)
	
Utility script(s) installed:
	mnconnect.sh

# stratum_remote.sh
This script will create a remote mining access point to stratum node (within a cluster).
This way, mining operation can be on seperate networks from the mining (stratum) node.

To run this install script successfully, you'll need the following information from the stratum node: HOSTKEY, TARGETADDRESS, (SSHPORT = 22), and (STRATUMPORT = 3333)

Note: Make sure to assign a static IP to this remote access point on the router!

Once setup and running, miners on the same local network can be directed to the following address:
    stratum+tcp://$HOSTNAME.local:3333

FYI:
    The "$USER/.ssh/authorized_keys" file contains administrator login keys.
    sudo systemctl status p2pssh@remote # View the status of the connection

Recommended Hardware:
    Rasperry Pi Zero 2 W
    Aluminum Passive Case
    OTG Micro USB Ethernet Adapter
    USB Power Supply
	
##################################### SUPPORT UTILITIES #############################################
# p2pconnect.sh // Install the p2p micronode connect utility (p2pconnect.sh)

# mnconnect.sh

# stmutility.sh ######### Still under active development #################
    Stratum utility



# Communication???? Back a directory...

# Goddady Dynamic DNS???
	



# payouts.sh ######### Still under active development #################

# teller.sh ######### Needs updated readme and comments, a few tweaks #################