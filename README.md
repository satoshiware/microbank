# Microbank

This repository contains all the necessary install scripts to setup a Bitcoin Service “₿anking” Node.
These nodes make up the technical infrastructure upon which a local ecosystem, based on Bitcoin and respective microcurrency, can flourish.

In the spirit of small “local banking”, the server hardware should be able to handle several thousand customers with peak usage of several hundred people simultaneously. 
The hardware can be divided into two classes: DEVELOPER and PRODUCTION. The <mark>developer</mark> server only needs enough power to manage a piece of the overall system with only a few clients;
however, it would be ideal to model it after the <mark>production</mark> server so all these install scripts will work on either one. Note: Make sure the CPU can handle Type 1 Virtualization using Linux’s KVM.

### **Developer Server**
- 8 Cores /w 16 to 32 GB of RAM
- 1 to 2 M.2 SSD(s) 1 to 4 TB (depending on applications being developed)
- Small SHA256D Miner (150W MAX)
- Examples (Aug 2024): 
  - Beelink Mini PC (SER6 | EQR6) w/ AMD Ryzen 9
  - GEEKOM A7 Mini PC AMD Ryzen 9
  - Avalon Nano 3

### **Production Server**
<mark>Built on a 12U Server Rack</mark>
- x2 24 Port 1U Patch Panel
- 24 Port 1U 1 Gbps Unmanaged Network Switch 
- 24 Port 1U 1 Gbps Unmanaged Switch (w/ 8+ Ports of POE+ @ > 80 Watts)
- 1U Rack Shelf Taking 2U Space (w/ Examples)
  - Router: X4 2.5 Gbps Ports /w x2 SPF+ Ports
    - Examples (Aug 2024)
      - Protectli VP6630 (Quality 2 x 16GB RAM & 1TB SSD) /w OPNsense
      - OPNsense DEC840
  - Modem (if needed) & Other Misc. Stuff
- 4U Server
- 2U UPS Battery Backup
- Latest Industrial SHA256D Miner

<mark>4U Server</mark>
- “Workstation Pro’” Hardware for Easy Sourcing
- 64 x86 Cores (128 ARM Cores) w/ AIO Cooler
- 256 GB Ram
- SPF+ NIC
- x2 16 PCI Channel Raid (4 x M.2)
- X8 M.2 4TB SSDs 

<mark>4U Server (Example Build - Aug 2024)</mark>
- ASUS Hyper M.2 x16 Gen5
- X8 SAMSUNG 990 PRO SSD 4TB PCIe 4.0 M.2
- 10Gtek PCI-E NIC (Single SFP+ Port)
  - 10Gtek SFP+ DAC Twinax Cable
- Threadripper 7980X (Socket sTR5)
  - 5.1 GHz
  - DDR5 5200
- ASUS Pro WS WRX90E-SAGE SE EEB
- Corsair RM1200x Shift Fully Modular ATX Power Supply
- SilverStone XE360-TR5
- x2 Kingston Fury Renegade Pro 128GB (4 x 32GB) ECC DDR5 5600 RAM
- SilverStone RM46-502-I 4U Chassis
- Potential Upgrades
  - 96 Core CPU
  - 512 GB RAM
  - (Add | Use) x16 Raid w/ 8 TB M.2 Drives
- Bonus Fun (Raid Storage Backup /w 64TB)
  - X2 ICY DOCK 4 Bay 2.5" (Using 5.25" Bay) Hot-Swappable MB014SP-B R1
  - X8 SAMSUNG 870 QVO SATA III SSD 8TB 2.5"
- Bitcoin Miner S21 Hyd. by Bitmain 

### **Security Access**
Utilize a Yubikey to access the server remotely via SSH. For security, all other built in remote tools will be disabled. Physical Access to the server is the same as root access; Run the server in a vault with some built-in self-destructing capabilities if possible.

### **Backup**
Critical data is encrypted and backed up off site (e.g. Amazon or Google cloud). Wallets, Encryption Keys, Passphrases, etc. are backed up onto a USB thumb drive and vaulted away. Use an obscure vault and location that is not in the same as the housing or the server.

### **Compatibility**
Scripts should be able to run both x86 and ARM (both 64 bit) and maybe even RISC-V at some point in the future.

### **Methodology**
Minimum Linux Install w/ KVM Type 1 Virtualized Containers
- VM1… Linux OS w/ Service1
- VM2… Linux OS w/ Service2
      <br>:
- VM(n-1)… QEMU Type 2 Virtualizer (Emulate x86, ARM, and RISC-V)
- VMn… Docker w/ Kubernetes

### **Services (Virtualized Servers)**
- Bitcoin Node
- Bitcoin Electrum Node
- Lightning Node
- Lighting WatchTower
- Lightning Address Server
- Microcurrency (Distribution Phase)
  - P2P Node
  - Wallet Node
  - Stratum (Mining) Node
  - Electrum Node
- Main Website
- Secure Online Check Out
- Blockchain Explorer
- Microcurrency Explorer
- Satoshi Coin Explorer
- Advanced Exchange
- Exchange Interface
- Email (Dovecot/Postfix/Rspamd/PostgreSQL)
- NTP Time
- Backup

# Initial Setup
- Download Debian ISO (AMD64 or ARM64): debian.org/distrib/netinst
  - Download & Run Latest Rufus Version (Windows): github.com/pbatard/rufus/releases
  - Connect a USB Drive (4GB+) & Select The Device in Rufus
  - Select “debian-xx.x.x-xxx64-netinst.iso” Image
  - Leave Most Settings @ Default Values
    - Partition scheme: 	GPT
    - Target system:	UEFI
  - Click “Start”
- Connect USB Drive to the microbank node
- Configure BIOS (microbank node) & Override Boot Device
  - Setup RAID Configurations
  - Configure NVME boot device
  - Setup One-Shot Boot Override to USB Drive
  - Save Configuration and Exit
- When Debian Install Screen Appears, Select “Install” and continue…
- Here are the settings we used for our installation. Adjust as needed.
  - Language: 		English
  - Territory:		United States
  - Keymap:		American English
  - Network Interface: 	exxxx
  - Hostname:	  az-microbank | az-dev
  - Domain Name:	local
  - Root Password:	*Leave Blank*
  - Verify Password:	*Leave Blank*
  - User’s Name:		*Leave Blank*
  - Username:		satoshi
  - Password:		satoshi
  - Verify Password	satoshi
  - Time Zone: 		Arizona
  - Partitioning Method:	Entire Disk with LVM (without software encryption)
    - Disk:			/dev/nvmexxx
    - Partitioning Method:	All files in one partition
    - <ins>*Remove existing logical volume data*</ins>
    - <ins>*Write changes and configure LVM*</ins>
    - Partitioning Size:	max
    - <ins>*Write changes to disk*</ins>
  - Mirror Country:	United States
  - Archive Mirror:		deb.debian.org
  - HTTP Proxy:		<Leave Blank>
  - Participate in Survey:	No
  - Software Install:	DESELECT ALL – SELECT “<ins>SSH server</ins>” ONLY
  - <ins>*Select continue to reboot*</ins>
- Login Remotely via SSH, Install git, and Get/Run the "base_setup.sh" script
  ```
  sudo apt-get -y install git
  cd ~; git clone https://github.com/satoshiware/microbank
  bash ./microbank/scripts/base_setup.sh
  ```
- Configure Static IP on Router & Make SSH port available everywhere
- Restart the computer
