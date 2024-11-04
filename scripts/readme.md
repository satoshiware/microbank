This is a list of Linux (Debian) scripts that are used to install and setup a BTC "Banking" Service
To execute any of these scripts, login as a sudo user (that is not root) and execute the following commands (substituting the $SCRIPT NAME variable accordingly):
    sudo apt-get -y install git
    cd ~; git clone https://github.com/satoshiware/microbank
    bash ./microbank/scripts/$SCRIPT_NAME.sh
    rm -rf microbank
    rm globals.env

pre_fork_micro(folder)
    Scipts to setup and operate a new microcurrency during the distribution period.

# bitcoin_node.sh
    Installs a Full Indexed Bitcoin Node.
    Be sure to forward the P2P port 8333 on the router to this Virtual Machine.

    In order for a new node to sync quickly, TEMPORARILY increase the RAM (e.g. 16 GB)
    and set dbcache to much higher number in the /etc/bitcoin.conf file (e.g. 8192)

    Hardware VM Recommendation:
        CPU:        8
        RAM:        8GB
        Storage:    2TB (NVMEs w/ RAID)

# bitcoin_wallet_node.sh
    Installs a Pruned Bitcoin Node that connects only to our Local Full Bitcoin Node.
    Used to load Satoshi Coins, redeem private keys, watch balances, receive mining rewards,
    and receive extra proceeds from btcpay & lightning channels.

    In order for a new node to sync quickly, TEMPORARILY increase the RAM (e.g. 16 GB), and vCPUs,
    and set dbcache to much higher number in the /etc/bitcoin.conf file (e.g. 8192)

    Hardware VM Recommendation:
        CPU:        1
        RAM:        2GB
        Storage:    128GB (NVMEs w/ RAID)

    Scripts Installed:
        wallu - Facilitate wallet activities including the loading of Satoshi Coins
        send_messages - Send emails or texts

# bitccoin_electrs.sh
    Installs an electrum server (electrs by Blockstream) for bitcoin.
    Original Documentation (ElectrumX): https://electrumx-spesmilo.readthedocs.io
    Repository (electrs): https://github.com/romanz/electrs
    Repository (electrs Blockstream Fork): https://github.com/Blockstream/electrs

    The initial sync is very RAM and DISK hungry! TEMPORARILY increase the RAM until synced and then run the
    "sudo fstrim -a" command when finished to return unused space back to the VM Host. If resources become
    too low, the guest OS may kill electrs. Use the following command to verify if it has ever been killed.
        sudo dmesg -T | egrep -i 'killed process'
    Use the following commands to view the system journal for electrs
        sudo journalctl -a -u electrs # Show the entire electrs journal
        sudo journalctl -f -a -u electrs # Continually follow latest updates
    During the compacting phases of the initial sync, verify changes in the "disk usage" of the electrs directory
        sudo du -h /var/lib/electrs
    Once sync is finished the ports will become active
        sudo ss -tulpn # Show active ports

    Once sync is complete, set up the router/firewall accordingly
        Port forward 50001 to port 50001 on the electrs server for non-encrypted JSON-RPC external communications.
        Using the HA Proxy, configure a TCP SSL reverse proxy from port 50002 to port 50001 for encrypted JSON-RPC communications.
        Setup HTTP(S) reverse proxy from 80(http)/443(https) to port 3000 using the subdomain of choice (e.g. btc-electrum.btcofaz.com).

    Hardware VM Recommendation:
        CPU:        8
        RAM:        16GB
        Storage:    3072GB (NVMEs w/ RAID; x6 Blockchain Size)

# bitcoin_explorer.sh
	Installs a bitcoin blockchain explorer.
	It requires a bitcoin full node and bitcoin electrum server for its data.

	HTTP Port: 3002
	The BTC Explorer is configured to operate with a reverse proxy.

	Hardware VM Recommendation:
        CPU:        4
        RAM:        4GB
        Storage:    128GB (NVMEs w/ RAID)

# lightning_node.sh
    Installs a lightning node

stratum_server.sh
    Installs a bitcoin mining pool

btcpay_server.sh
    Installs a btcpay server
    Needs access to a bit

cross-compile_btc.sh
    Cross compiles bitcoin (64bit) with microcurrency integration
    Supported Processors: x86, ARM
    Source code: https://github.com/satoshiware/bitcoin

# apache2_wp_website.sh
This script will install apache with a single wordpress site.

(Optional) Installs a "Let's Encrypt" SSL Certificate.
Make sure your DNS records are already configured if installing an SSL certificate from Let's Encrypt.

Recommended Hardware:
    Rasperry Pi Compute Module 4: CM4004032 (w/ Compute Blade)
    4GB RAM
    eMMC 32 GB
    Netgear 5 Port Switch (PoE+ @ 120W)

# add_wp_website.sh
    Add a website endpoint to a preexisting website server
