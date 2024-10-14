This is a list of Linux (Debian) scripts that are used to install and setup a BTC "Banking" Service
To execute any of these scripts, login as a sudo user (that is not root) and execute the following commands (substituting the $SCRIPT NAME variable accordingly):
    sudo apt-get -y install git
    cd ~; git clone https://github.com/satoshiware/microbank
    bash ./microbank/scripts/$SCRIPT_NAME.sh
    rm -rf microbank

pre_fork_micro(folder)
    Scipts to setup and operate a new microcurrency during the distribution period.

bitcoin_node.sh
    Installs a Full Indexed Bitcoin Node.
    Be sure to forward the P2P port 8333 on the router to this Virtual Machine

    JSON RPC Authentication:
        user: satoshi
        pass: satoshi
    Hardware VM Recommendation:
        CPU:        4 vCore Min / 8 vCore Max
        RAM:        2GB Min / 8GB Max
        Storage:    2TB

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

electrs_server.sh
    Installs an electrum server for bitcoin.
    Connects with a bitcoin node via SSH Tunneling and port forwarding.
        With required Bitcoin RPC commands whitlisted.
    Source code (rust): https://github.com/romanz/electrs

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
