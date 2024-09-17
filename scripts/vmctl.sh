#!/bin/bash

# Make sure we are not running as root, but that we have sudo privileges.
if [ "$(id -u)" = "0" ]; then
   echo "This script must NOT be run as root (or with sudo)!"
   exit 1
elif [ "$(sudo -l | grep '(ALL : ALL) ALL' | wc -l)" = 0 ]; then
   echo "You do not have enough sudo privileges!"
   exit 1
fi

# See which vmctl parameter was passed and execute accordingly
if [[ $1 = "--help" ]]; then # Show all possible paramters
    cat << EOF
    Options:
      --help        Display this help message and exit
      --install     Install (or upgrade) this script (vmctl) in /usr/local/sbin (/satoshiware/microbank/scripts/vmctl.sh)
      --create      Create new VM instance
      --shutdown    Freeze all VMs and shutdown the host server
      --reboot      Freeze all VMs and reboot the host server
      --delete      Deletes a VM instance; Parameters: $VM_NAME
EOF

elif [[ $1 == "--install" ]]; then # Install (or upgrade) this script (vmctl) in /usr/local/sbin (/satoshiware/microbank/scripts/vmctl.sh)
    echo "Installing this script (vmctl) in /usr/local/sbin/"
    if [ -f /usr/local/sbin/vmctl ]; then
        echo "This script (vmctl) already exists in /usr/local/sbin!"
        read -p "Would you like to upgrade it? (y|n): "
        if [[ "${REPLY}" = "y" || "${REPLY}" = "Y" ]]; then
            sudo rm /usr/local/sbin/vmctl
            cd ~; git clone https://github.com/satoshiware/microbank
            bash ~/microbank/scripts/pre_fork_micro/vmctl.sh --install
            rm -rf microbank
            exit 0
        else
            exit 0
        fi
    fi

    sudo cat $0 | sudo tee /usr/local/sbin/vmctl > /dev/null
    sudo chmod +x /usr/local/sbin/vmctl

elif [[ $1 == "--create" ]]; then # Create new VM instance
    read -p "Guest OS Name (No Spaces; 14 Char's MAX): " VM_NAME
    read -p "Amount of RAM (Mbytes; e.g. 4096): " RAM
    read -p "Maximum Amount of RAM (Mbytes; e.g. 8192): " MAXRAM
    read -p "Number of vCPUs (e.g. 1): " CPUS
    read -p "Maximum Number of vCPUs (e.g. 4): " MAXCPUS
    read -p "Virtual Disk Size (GBs; e.g. 20): " DISKSIZE
    read -p "Image file location (Relative to \"/var/lib/libvirt/images\"; e.g. \".\"): " DRIVE

    URL_ISO="/dc/iso/debian-install.iso"
    PRESEED_CFG="/dc/iso/preseed.cfg"

    sudo virt-install \
        --connect=qemu:///system \
        --name ${VM_NAME:0:14} \
        --memory memory=${MAXRAM},currentMemory=${RAM} \
        --vcpus maxvcpus=${MAXCPUS},vcpus=${CPUS} \
        --cpu host-passthrough \
        --network bridge=bridge0 \
        --location ${URL_ISO} \
        --initrd-inject ${PRESEED_CFG} \
        --os-variant debian11 \
        --disk path=/var/lib/libvirt/images/${DRIVE}/${VM_NAME:0:14}.qcow2,size=${DISKSIZE},format=qcow2,cache=none,discard=unmap \
        --tpm model='tpm-crb',type=emulator,version='2.0' \
        --rng /dev/urandom,model=virtio \
        --rng /dev/random,model=virtio \
        --channel type=unix,target.type=virtio,target.name=org.qemu.guest_agent.0 \
        --graphics none \
        --extra-args "auto=true hostname=\"${VM_NAME:0:14}\" domain=\"local\" console=ttyS0,115200n8 serial" \
        --console pty,target_type=serial \
        --noautoconsole \
        --autostart \
		--watchdog model=i6300esb,action=reset \
        --boot uefi

sudo apt-get -y install watchdog # Install Watchdog
cat << EOF | sudo tee /etc/watchdog.conf # Configure Watchdog
watchdog-device = /dev/watchdog
log-dir =  /var/log/watchdog
realtime = yes
priority = 1
EOF

#/etc/default/watchdog file and set the watchdog_module to i6300esb
sudo systemctl enable watchdog
#Fully power off the VM (not restart). This is important as it'll allow it to adopt the new hardware configuration.
#Power the VM back on and check the watchdog module is up and working by running dmesg | grep i6300. You should see something like the below:
#Code:

#[    7.249538] i6300ESB timer 0000:00:04.0: initialized. heartbeat=30 sec (nowayout=0)

#Everything is now configured and the only thing left to do is to give it a test. To run a test, trigger a kernel panic by running echo c > /proc/sysrq-trigger. After a short while (60 seconds or so) you should see the VM automatically reset, and you're done! I hope you find this useful.







    echo ""; echo "Note: When install is complete (~5 Minutes), it will shutdown (and stay there) 'till the host-server reboots or 'till it's manually started."
    echo "Take advantage to configure a static IP in the router for this new VM."

#--watchdog model=i6300esb,action=reset         Configure a guest watchdog device
#--launchSecurity sev??
#   Enable AMD's "Secure Encrypted Virtualization" (SEV)
#   Waiting for support for Intel's "Trust Domain Extensions" (TDX)
# install watchdog, tune

elif [[ $1 == "--shutdown" ]]; then # Freeze all VMs and shutdown the host server
    mapfile -t vm_array < <( sudo virsh list --all --name )
    while read -r vm; do
        if [ ! -z "$vm" ]; then
            sudo virsh managedsave $vm 2> /dev/null # Do this to each one
        fi
    done < <( printf '%s\n' "${vm_array[@]}")

    sudo shutdown -h +1
    echo "VMs are being put into saved states..."
    echo "Shutting down in 5 minutes..."

elif [[ $1 == "--reboot" ]]; then # Freeze all VMs and reboot the host server
    mapfile -t vm_array < <( sudo virsh list --all --name )
    while read -r vm; do
        if [ ! -z "$vm" ]; then
            sudo virsh managedsave $vm 2> /dev/null # Do this to each one
        fi
    done < <( printf '%s\n' "${vm_array[@]}")

    sudo shutdown -r +5
    echo "VMs are being put into saved states..."
    echo "Restarting in 5 minutes..."

elif [[ $1 == "--delete" ]]; then # Deletes a VM instance; Parameters: $VM_NAME
    sudo virsh destroy ${2}
    sudo virsh managedsave-remove ${2}
    sudo virsh undefine --nvram ${2}
    sudo rm /var/lib/libvirt/images/${2}.qcow2 # Remove VM (Only if it is shutdown)

else
    $0 --help
    echo "Script Version 0.01"
fi