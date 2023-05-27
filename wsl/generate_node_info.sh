#!/bin/bash

mkdir -p ~/backup

echo "This file contains important information on your \"$(hostname)\" micronode." | tee ~/backup/$(hostname).info > /dev/null
echo "It can be used to establish p2p and stratum connections over ssh." | tee -a ~/backup/$(hostname).info > /dev/null
echo "" | tee -a ~/backup/$(hostname).info > /dev/null

read -p "What is your name? "; echo "Name: $REPLY" | tee -a ~/backup/$(hostname).info > /dev/null
read -p "What is the hub level? "; echo "Level: $REPLY" | tee -a ~/backup/$(hostname).info > /dev/null
echo "Time Stamp: $(date +%s)" | tee -a ~/backup/$(hostname).info > /dev/null
echo "" | tee -a ~/backup/$(hostname).info > /dev/null

read -p "What is the address to this micronode? "; echo "Address: $REPLY" | tee -a ~/backup/$(hostname).info > /dev/null
echo "" | tee -a ~/backup/$(hostname).info > /dev/null

echo "SSH Port: $(sudo cat /etc/ssh/sshd_config | grep 'Port ' | sed 's/Port *//')" | tee -a ~/backup/$(hostname).info > /dev/null
echo "Micro Port: $(sudo cat /etc/bitcoin.conf | grep '^port=' | sed 's/port=*//')" | tee -a ~/backup/$(hostname).info > /dev/null
echo "Stratum Port:" | tee -a ~/backup/$(hostname).info > /dev/null
echo "" | tee -a ~/backup/$(hostname).info > /dev/null

echo "Host Key (Public): $(sudo cat /etc/ssh/ssh_host_ed25519_key.pub | sed 's/ root@.*//')" | tee -a ~/backup/$(hostname).info > /dev/null
echo "P2P Key (Public): $(sudo cat /root/.ssh/p2pkey.pub)" | tee -a ~/backup/$(hostname).info > /dev/null


############# todo: the Micro port is gonna be different if it was not changed in the bitcoin.conf. what's the backup?
########## havn't done stratum port yet. gotta a solution that will work on level1 and level2???
############ the P2p service needs updated if we are gonna change ports.

########### on level 1, what about doing the pass through port???? that was all theorectical 'till now. 
