#!/bin/bash
####################################################################################################
# This file generates the binanries (and sha 256 checksums) for bitcoin core
# from the https://github.com/bitcoin/bitcoin repository. This script was made for linux
# x86 64 bit and has been tested on WSL with Debian.
####################################################################################################

# Make sure we are not running as root, but that we have sudo privileges.
if [ "$(id -u)" = "0" ]; then
   echo "This script must NOT be run as root (or with sudo)!"
   echo "if you need to create a sudo user (e.g. satoshi), run the following commands:"
   echo "   sudo adduser satoshi"
   echo "   sudo usermod -aG sudo satoshi"
   echo "   sudo su satoshi # Switch to the new user"
   exit 1
elif [ "$(sudo -l | grep '(ALL : ALL) ALL' | wc -l)" = 0 ]; then
   echo "You do not have enough sudo privileges!"
   exit 1
fi
cd ~; sudo pwd # Print Working Directory; have the user enable sudo access if not already.

echo "Generated binaries and related files are transfered to the \"./bitcoin/bin\" directory."
echo "Binaries are created from the latest master branch commit @ https://github.com/bitcoin/bitcoin."
read -p "Press [Enter] key to continue..."

###Update/Upgrade
sudo apt-get -y update
sudo DEBIAN_FRONTEND=noninteractive apt-get -y install --only-upgrade openssh-server # Upgrade seperatly to ensure non-interactive mode
sudo apt-get -y upgrade

###Install Essential Tools
sudo apt-get -y install build-essential libtool autotools-dev automake pkg-config bsdmainutils curl zip
sudo apt-get -y install pkg-config # Helper tool used when compiling applications and libraries. Necessary?

###Install SQLite (Required For The Descriptor Wallet)
sudo apt-get -y install libsqlite3-dev

###Download Bitcoin and switch to the desired branch and tag
sudo apt-get -y install git
git clone https://github.com/bitcoin/bitcoin ./bitcoin
read -p "Target Branch (default = \"master\"): " BRANCH; if [ -z $BRANCH ]; then BRANCH="master"; fi
read -p "Desired TAG (default = \"v27.0\"): " TAG; if [ -z $TAG ]; then TAG="v27.0"; fi
cd bitcoin
git switch $BRANCH
git checkout tags/$TAG

###Install Cross Compilation Dependencies
#Linux x86 64-bit are already installed
sudo apt-get -y install g++-aarch64-linux-gnu binutils-aarch64-linux-gnu #ARM 64-bit
sudo apt -y install g++-mingw-w64-x86-64-posix #Windows x86 64-bit

###################################### x86 64 Bit ##############################################
###Prepare the Cross Compiler for "x86 64 Bit"
cd ./bitcoin/depends
sudo make clean
sudo make HOST=x86_64-pc-linux-gnu NO_QT=1 NO_QR=1 NO_UPNP=1 NO_NATPMP=1 NO_BOOST=1 NO_LIBEVENT=1 NO_ZMQ=1 NO_USDT=1 -j $(($(nproc)+1)) #x86 64-bit

###Make Configuration
cd ..
./autogen.sh # Make sure Bash's current working directory is the bitcoin directory

### Select Configuration for "x86 64 Bit"
CONFIG_SITE=$PWD/depends/x86_64-pc-linux-gnu/share/config.site ./configure

###Compile /w All Available Cores & Install
make clean
make -j $(($(nproc)+1))

###Create Compressed Install Files in ./bin Directory
rm -rf ./mkinstall
rm -rf ./bitcoin-install
make install DESTDIR=$PWD/mkinstall
mv ./mkinstall/usr/local ./bitcoin-install
mkdir bin

###Compress Install Files for "x86 64 Bit"
tar -czvf ./bin/${1}_bitcoin-x86_64-linux-gnu.tar.gz ./bitcoin-install #x86 64-Bit

###################################### ARM 64 Bit ##############################################
###Prepare the Cross Compiler for "ARM 64 Bit"
cd ./depends
sudo make clean
sudo make HOST=aarch64-linux-gnu NO_QT=1 NO_QR=1 NO_UPNP=1 NO_NATPMP=1 NO_BOOST=1 NO_LIBEVENT=1 NO_ZMQ=1 NO_USDT=1 -j $(($(nproc)+1)) #ARM 64-bit

###Make Configuration
cd ..
./autogen.sh # Make sure Bash's current working directory is the bitcoin directory

### Select Configuration for "ARM 64 Bit"
CONFIG_SITE=$PWD/depends/aarch64-linux-gnu/share/config.site ./configure

###Compile /w All Available Cores & Install
make clean
make -j $(($(nproc)+1))

###Create Compressed Install Files in ./bin Directory
rm -rf ./mkinstall
rm -rf ./bitcoin-install
make install DESTDIR=$PWD/mkinstall
mv ./mkinstall/usr/local ./bitcoin-install
mkdir bin

###Compress Install Files for "ARM 64 Bit"
tar -czvf ./bin/${1}_bitcoin-aarch64-linux-gnu.tar.gz ./bitcoin-install #ARM 64-Bit

###################################### Windows x86 64 Bit ##############################################
###Prepare the Cross Compiler for "Windows x86 64 Bit"
cd ./depends
sudo make clean
sudo make HOST=x86_64-w64-mingw32 NO_QT=1 NO_QR=1 NO_UPNP=1 NO_NATPMP=1 NO_BOOST=1 NO_LIBEVENT=1 NO_ZMQ=1 NO_USDT=1 -j $(($(nproc)+1)) #Windows (x86 64-bit)

###Make Configuration
cd ..
./autogen.sh # Make sure Bash's current working directory is the bitcoin directory

### Select Configuration for "Windows x86 64 Bit"
CONFIG_SITE=$PWD/depends/x86_64-w64-mingw32/share/config.site ./configure
###Compile /w All Available Cores & Install
make clean
make -j $(($(nproc)+1))

###Create Compressed Install Files in ./bin Directory
rm -rf ./mkinstall
rm -rf ./bitcoin-install
make install DESTDIR=$PWD/mkinstall
mv ./mkinstall/usr/local ./bitcoin-install
mkdir bin

###Compress Install Files for "Windows x86 64 Bit"
zip -ll -X -r ./bin/${1}_bitcoin-win64.zip ./bitcoin-install #Windows x86 64-bit

###################################### Calculate Hashes ##############################################
sha256sum ./bin/${1}_bitcoin-aarch64-linux-gnu.tar.gz > ./bin/${1}_SHA256SUMS
sha256sum ./bin/${1}_bitcoin-win64.zip >> ./bin/${1}_SHA256SUMS
sha256sum ./bin/${1}_bitcoin-x86_64-linux-gnu.tar.gz >> ./bin/${1}_SHA256SUMS