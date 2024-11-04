This is a list of scripts that are used to install and setup a "micronode" cluster.
What is a micronode cluster?
Basically, it's a few nodes, each with a specific task, with the bitcoin core installed and running a microcurrency.

To execute any of these scripts, login as a sudo user (that is not root) and execute the following commands (substituting the $SCRIPT NAME variable accordingly):
    sudo apt-get -y install git
    cd ~; git clone https://github.com/satoshiware/microbank
    bash ./microbank/scripts/pre_fork_micro/$SCRIPT_NAME.sh
    rm -rf ~/microbank # After reboot, delete the microbank folder from the home directory.
    sudo reboot now

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
    send_messages.sh
    dynamic_dns.sh


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
    send_messages.sh

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
    send_messages.sh

# electrs_node.sh
    Installs a full microcurrency node and an electrum server (electrs by Blockstream) to to accompany it.

    Microcurrency Node: Used to provide a whitelisted JSON-RPC inteferace on the private network to provide the backend for the electrum
    server and other services (e.g. microcurrency blockchain explorer).

    Electrum Server:
        Original Documentation (ElectrumX): https://electrumx-spesmilo.readthedocs.io
        Repository (electrs): https://github.com/romanz/electrs
        Repository (electrs Blockstream Fork): https://github.com/Blockstream/electrs
        The Repository https://github.com/satoshiware/rust-bitcoin is a forked with newly created branches to support individual
            microcurrencies (two for each; including one for bech32). The install script will override the electrs/Cargo.toml
            file to use the respective branch on the forked rust-bitcoin in the Satoshiware repository.

    If resources become too low, the guest OS may kill bitcoind or electrs. The following command to verify if something has been killed.
        sudo dmesg -T | egrep -i 'killed process'
    Use the following commands to view the system journal for electrs
        sudo journalctl -a -u electrs # Show the entire electrs journal
        sudo journalctl -f -a -u electrs # Continually follow latest updates
    During the compacting phases of the initial sync, verify changes in the "disk usage" of the electrs directory
        sudo du -h /var/lib/electrs
    Once sync is finished the ports will become active
        sudo ss -tulpn # Show active ports

    Once sync is complete, set up the router/firewall accordingly
        Port forward 51001 to port 51001 on the electrs server for non-encrypted JSON-RPC external communications.
        Using the HA Proxy, configure a TCP SSL reverse proxy from port 51002 to port 51001 for encrypted JSON-RPC communications.
        Setup HTTP(S) reverse proxy from 80(http)/443(https) to port 13000 using the subdomain of choice (e.g. btc-electrum.btcofaz.com).

    mnconnect.sh utility script has been installed. It's used to connect to the microcurrency p2p node.

    Hardware VM Recommendation:
        CPU:        8
        RAM:        8GB
        Storage:    1024GB (NVMEs w/ RAID)

# blockchain_explorer.sh <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
	Installs a microcurrency blockchain explorer.
	It requires a microcurrency full node and microcurrency electrum server for its data.

	HTTP Port: 3002
	The Microcurrency Explorer is configured to operate with a reverse proxy.

	Hardware VM Recommendation:
        CPU:        4
        RAM:        4GB
        Storage:    128GB (NVMEs w/ RAID)
		
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

# gekko_host.sh
This script creates a host (using cgminer) to operate miners produced by Gekko Science.

Once setup and running, connect Gekko miners to this host and they will automatically start running.

Direct your web browser to "http://$(hostname).local" to see mining stats.
See cgminer log on the web server @ http://$(hostname).local/log.html (updated every 5 minutes)
See latest cgminer screen shot @ http://$(hostname).local/screen.html (updated every 5 minutes)

Use the "cgctl" utility (installed with this script) to start, stop, and restart cgminer
as well as generate logs and screen shots for the webpage.

FYI:
    The "$USER/.ssh/authorized_keys" file contains administrator login keys.
    The "/etc/cgminer.conf" file contains the cgminer configuration.
    sudo systemctl status cgminer # View the running status of cgminer.
    The "/var/log/cgminer/cgminer.log" file contains the logging information.
    Support webpage: https://kano.is/gekko.php

Recommended Hardware:
    Rasperry Pi Zero 2 W
    Aluminum Passive Case
    micro usb hub (to connect the miners)
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