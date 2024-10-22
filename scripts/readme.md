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

    Hardware VM Recommendation:
        CPU:        4 vCore Min / 8 vCore Max
        RAM:        2GB Min / 8GB Max
        Storage:    2TB

    # Need to rebuild with updated spec's....move these comments to globals.env when done....
    # Reverse proxy port 80 (http) & 443 (https) to btc-electrum server to the http port 3000
    #   http://btc-electrum.btcofaz.com | https://btc-electrum.btcofaz.com
    # Reverse proxy port 50001 to btc-electrum server to port 50001 (jsonrpc)
    #   ssl://btc-electrum.btcofaz.com:50001
    # Port forwarded 50002 (Without SSL) to btc-electrum server to port 50001 (jsonrpc)
    # Where's the log file? Check/Update /var/log link.
    # --electrum-announce - announce the electrum server on the electrum p2p server discovery network.
    # --electrum-hosts <json> - a json map of the public hosts where the electrum server is reachable, in the server.features format.

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
