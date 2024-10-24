This is a list of Linux (Debian) scripts that are used to install and setup a BTC "Banking" Service
To execute any of these scripts, login as a sudo user (that is not root) and execute the following commands (substituting the $SCRIPT NAME variable accordingly):
    sudo apt-get -y install git
    cd ~; git clone https://github.com/satoshiware/microbank
    bash ./microbank/scripts/$SCRIPT_NAME.sh
    rm -rf microbank
    rm globals.env

pre_fork_micro(folder)
    Scipts to setup and operate a new microcurrency during the distribution period.

bitcoin_node.sh
    Installs a Full Indexed Bitcoin Node.
    Be sure to forward the P2P port 8333 on the router to this Virtual Machine.

    In order for a new node to sync quickly, TEMPORARILY increase the RAM (e.g. 16 GB)
    and set dbcache to much higher number in the /etc/bitcoin.conf file (e.g. 8192)

    Hardware VM Recommendation:
        CPU:        8
        RAM:        8GB
        Storage:    2TB (NVMEs w/ RAID)

bitcoin_wallet_node.sh
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

btc_electrs.sh
    Installs an electrum server (electrs by Blockstream) for bitcoin.

    HTTP server is available on port 3000 from any IP #### Configure HTTPS forwarding @ the Reverse Proxy! ####
    JSON RPC for electrs connections on port 50001 from any IP. #### Configure SSL forwarding @ the Reverse Proxy! ####
    Prometheus monitoring connection access on port 4224 is allowed from any local IP.

    The initial sync is very RAM and DISK hungry! TEMPORARILY increase the RAM (e.g. 32 GB) and PERMANENTLY make the
    disk drive x4 the Blockchain size. Run the "sudo fstrim -a" when finished to return unused space back to the VM Host.
    The viewpoints provided into the progress of the initial sync and operation of electrs are minimal. You can view the
    log on the bitcoin node to ensure rpc commands are going through. Also, the size and contents of the /var/lib/electrs
    directory, on this VM, can be observed indicating progress. Note: Near sync completion the rocks DB will be compacted
    and size will be reduced by more than 50%. See ~/readme.txt on the VM for more doable activities.

    Note: Use the following command to see if there are any messages indicating the guest OS has ever killed the electrs
    process for low memory resources
        sudo dmesg -T | egrep -i 'killed process'

    Hardware VM Recommendation:
        CPU:        8
        RAM:        16GB
        Storage:    2048GB (NVMEs w/ RAID; x4 Blockchain Size)

lightning_node.sh
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
