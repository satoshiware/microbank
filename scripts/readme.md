Linux (Debian) Scripts

pre_fork_micro(folder)
	Scipts to setup and operate a new microcurrency during the distribution period.

bitcoin_node.sh
	Installs a bitcoin node

bitnode.sh
	Command line utility to simplify the interface with the Bitcoin node.

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

apache2_wp_website.sh
	Install a wordpress website server

add_wp_website.sh
	Add a website endpoint to a preexisting website server
