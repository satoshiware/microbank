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
      --sync        Synchronize the system clock of each VM with the RTC (used with cronjob @reboot)
      --backup      Backup all pertinent VM files to ~/rsbakcup
      --restore     Restore backup files to \$VM_NAME @ /home/satoshi/restore; Parameters: \$VM_NAME
      --delete      Deletes a VM instance; Parameters: \$VM_NAME
EOF

elif [[ $1 == "--install" ]]; then # Install (or upgrade) this script (vmctl) in /usr/local/sbin (/satoshiware/microbank/scripts/vmctl.sh)
    echo "Installing this script (vmctl) in /usr/local/sbin/"
    if [ -f /usr/local/sbin/vmctl ]; then
        echo "This script (vmctl) already exists in /usr/local/sbin!"
        read -p "Would you like to upgrade it? (y|n): "
        if [[ "${REPLY}" = "y" || "${REPLY}" = "Y" ]]; then
            sudo rm /usr/local/sbin/vmctl
            cd ~; git clone https://github.com/satoshiware/microbank
            bash ~/microbank/scripts/vmctl.sh --install
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
    cd /var/lib/libvirt/images; echo ""; echo "Image File Locations:"; echo "    ."; sudo find ./ -type l | sed 's/^.\//    /'; echo ""
    read -p "Image File Location (Relative to \"/var/lib/libvirt/images\"; e.g. \".\"): " DRIVE

    $0 --create_preloaded $VM_NAME $RAM $MAXRAM $CPUS $MAXCPUS $DISKSIZE $DRIVE

elif [[ $1 == "--create_preloaded" ]]; then # Create new VM instance w/ preloaded values
    VM_NAME=$2; RAM=$3; MAXRAM=$4; CPUS=$5; MAXCPUS=$6; DISKSIZE=$7; DRIVE=$8; MAC=$9

    # Let user know status of encrypted VM capabilities
    echo ""; echo "TODO: AMD's \"Secure Encrypted Virtualization\" (SEV) w/ \"--launchSecurity sev\" has yet to be added to this script."
    echo "Intel's \"Trust Domain Extensions\" (TDX) is still not availble in QEMU/KVM"

    # If MAC address is defined, then format variable properly
    if [[ ! -z $MAC ]]; then
        MAC=",mac=$MAC"
    fi

    # Remove any previous known hosts with identical name
    ssh-keygen -f "/home/satoshi/.ssh/known_hosts" -R "$VM_NAME.local" 2> /dev/null
    ssh-keygen -f "/home/satoshi/.ssh/known_hosts" -R "$VM_NAME" 2> /dev/null

    URL_ISO="/dc/iso/debian-install.iso"
    PRESEED_CFG="/dc/iso/preseed.cfg"

    sudo virt-install \
        --connect=qemu:///system \
        --name ${VM_NAME:0:14} \
        --memory memory=${MAXRAM},currentMemory=${RAM} \
        --vcpus maxvcpus=${MAXCPUS},vcpus=${CPUS} \
        --cpu host-passthrough \
        --network bridge=bridge0$MAC \
        --location ${URL_ISO} \
        --initrd-inject ${PRESEED_CFG} \
        --os-variant debian11 \
        --disk path=/var/lib/libvirt/images/${DRIVE}/${VM_NAME:0:14}.qcow2,size=${DISKSIZE},format=qcow2,cache=none,discard=unmap \
        --tpm model='tpm-crb',type=emulator,version='2.0' \
        --rng /dev/urandom,model=virtio \
        --channel type=unix,target.type=virtio,target.name=org.qemu.guest_agent.0 \
        --graphics none \
        --extra-args "auto=true hostname=\"${VM_NAME:0:14}\" domain=\"local\" console=ttyS0,115200n8 serial" \
        --console pty,target_type=serial \
        --noautoconsole \
        --autostart \
        --watchdog model=i6300esb,action=reset \
        --boot uefi

    # Wait 'till setup is finished to restart machine
    finished=0; echo ""; echo -n "Waiting 'till \"$VM_NAME\" VM instance is done installing/shutdown to then start/continue"
    while [[ ${finished} -eq 0 ]]; do
        sleep 1
        echo -n "."
        if [ $(sudo virsh list --all | grep "running" | grep "$VM_NAME" | wc -c) -eq 0 ]; then
            finished=1
            sleep 3; echo ""; sudo virsh start $VM_NAME
        fi
    done

    # Wait 'till new VM is finished booting
    finished=0; echo ""; echo -n "Waiting 'till \"$VM_NAME\" VM instance is finished booting"
    while [[ ${finished} -eq 0 ]]; do
        sleep 1
        echo -n "."
        PID=$(sudo virsh -c qemu:///system qemu-agent-command $VM_NAME "{\"execute\":\"guest-exec\",\"arguments\":{\"path\":\"/usr/bin/ls\",\"arg\":[],\"capture-output\":true}}" 2> /dev/null | cut -d ":" -f 3 | sed 's/}}//')
        if [[ ! -z $PID ]]; then
            finished=1
            echo ""; echo "Boot Successful"
        fi
    done

    # Wait here 'till user has setup a static IP for the new VM in the OPNsense/PFsense router
    echo "This is the best time to setup a STATIC IP for the \"$VM_NAME\" VM in your OPNsense/PFsense router."
    if [[ ! -z $MAC ]]; then
        echo "Note: A MAC address was provided; this may be indicative you already have a STATIC IP setup."
        read -p "Press the enter key when you're ready..."
    else
        read -p "Press the enter key when you're finished..."
        read -p "Are you sure you are finished?... Press the enter key to continue..."
        read -p "Are you REALLY sure?... Press the enter key to continue..."
    fi

    # Install git on new instance
    PID=$(sudo virsh -c qemu:///system qemu-agent-command $VM_NAME "{\"execute\":\"guest-exec\",\"arguments\":{\"path\":\"/usr/bin/apt-get\",\"arg\":[\"-y\",\"install\",\"git\"],\"capture-output\":true}}" | cut -d ":" -f 3 | sed 's/}}//')
    finished=0; echo ""; echo -n "Installing \"git\" on the \"$VM_NAME\" VM instance"
    while [[ ${finished} -eq 0 ]]; do
        sleep 1
        echo -n "."
        STATUS=$(sudo virsh -c qemu:///system qemu-agent-command $VM_NAME "{\"execute\":\"guest-exec-status\",\"arguments\":{\"pid\":$PID}}" 2> /dev/null)
        if [[ $(echo $STATUS | jq '.return.exited') == "true" || -z $STATUS ]]; then
            finished=1
            echo ""; echo $STATUS | jq -r '.return."out-data"' | base64 --decode
            echo -n "Exit Code: "; echo $STATUS | jq '.return.exitcode'
        fi
    done

    # Clone microbank repository from Satoshiware
    PID=$(sudo virsh -c qemu:///system qemu-agent-command $VM_NAME "{\"execute\":\"guest-exec\",\"arguments\":{\"path\":\"/usr/bin/git\",\"arg\":[\"clone\",\"https://github.com/satoshiware/microbank\",\"/home/satoshi/microbank\"],\"capture-output\":true}}" | cut -d ":" -f 3 | sed 's/}}//')
    finished=0; echo ""; echo -n "Cloning the microbank repository from Satoshiware on the \"$VM_NAME\" VM instance"
    while [[ ${finished} -eq 0 ]]; do
        sleep 1
        echo -n "."
        STATUS=$(sudo virsh -c qemu:///system qemu-agent-command $VM_NAME "{\"execute\":\"guest-exec-status\",\"arguments\":{\"pid\":$PID}}" 2> /dev/null)
        if [[ $(echo $STATUS | jq '.return.exited') == "true" || -z $STATUS ]]; then
            finished=1
            echo ""; echo $STATUS | jq -r '.return."err-data"' | base64 --decode
            echo -n "Exit Code: "; echo $STATUS | jq '.return.exitcode'
        fi
    done

    # Run the vm_setup.sh script (shuts down the VM when finished)
    VMKEY=$(cat /home/satoshi/.ssh/vmkey.pub)
    PID=$(sudo virsh -c qemu:///system qemu-agent-command $VM_NAME "{\"execute\":\"guest-exec\",\"arguments\":{\"path\":\"/usr/bin/bash\",\"arg\":[\"/home/satoshi/microbank/scripts/vm_setup.sh\",\"${VMKEY}\"],\"capture-output\":true}}" | cut -d ":" -f 3 | sed 's/}}//')
    finished=0; echo ""; echo -n "Running the \"vm_setup.sh\" script on the \"$VM_NAME\" VM instance"
    while [[ ${finished} -eq 0 ]]; do
        sleep 1
        echo -n "."
        STATUS=$(sudo virsh -c qemu:///system qemu-agent-command $VM_NAME "{\"execute\":\"guest-exec-status\",\"arguments\":{\"pid\":$PID}}" 2> /dev/null)
        if [[ $(echo $STATUS | jq '.return.exited') == "true" || -z $STATUS ]]; then
            finished=1
            echo ""; echo "Shutting Down..."
        fi
    done

    # Wait 'till shutdown is finished to restart machine
    finished=0; echo ""; echo -n "Waiting 'till \"$VM_NAME\" VM instance is done shutting down to restart"
    while [[ ${finished} -eq 0 ]]; do
        sleep 1
        echo -n "."
        if [ $(sudo virsh list --all | grep "running" | grep "$VM_NAME" | wc -c) -eq 0 ]; then
            finished=1
            sleep 3; echo ""; sudo virsh start $VM_NAME
        fi
    done

    # Wait 'till new VM is finished booting
    finished=0; echo ""; echo -n "Waiting 'till \"$VM_NAME\" VM instance is finished booting"
    while [[ ${finished} -eq 0 ]]; do
        sleep 1
        echo -n "."
        PID=$(sudo virsh -c qemu:///system qemu-agent-command $VM_NAME "{\"execute\":\"guest-exec\",\"arguments\":{\"path\":\"/usr/bin/ls\",\"arg\":[],\"capture-output\":true}}" 2> /dev/null | cut -d ":" -f 3 | sed 's/}}//')
        if [[ ! -z $PID ]]; then
            finished=1
            echo ""; echo "Boot Successful and ALL DONE!"
        fi
    done

    # Write to log
    if [[ ! -f ~/vm-creation.log ]]; then
        echo "                         VM_NAME         RAM  /  MAX (MB)      vCPU / MAX      Disk Size (GB)      Location    MAC                Description" > ~/vm-creation.log
        echo "-----------------------------------------------------------------------------------------------------------------------------------------------------------" >> ~/vm-creation.log
    fi
    read -p "Enter description for this VM: " DESCRIPTION
    MAC=$(sudo virsh domifaddr $VM_NAME --source agent | grep -io 'e.*[0-9A-F]\{2\}\(:[0-9A-F]\{2\}\)\{5\}' | tr -s ' ' | cut -d " " -f 2)
    echo -n "vmctl --create_preloaded " >> ~/vm-creation.log
    printf "%-15s %-7s %-13s %-6s %-8s %-19s %-11s %-18s # %-0s - $(date)\n" "${VM_NAME}" "${RAM}" "${MAXRAM}" "${CPUS}" "${MAXCPUS}" "${DISKSIZE}" "${DRIVE}" "${MAC}" "${DESCRIPTION}" >> ~/vm-creation.log

elif [[ $1 == "--shutdown" ]]; then # Freeze all VMs and shutdown the host server
    mapfile -t vm_array < <( sudo virsh list --all --name | tr -s '\n' )
    while read -r vm; do
        if [ ! -z "$vm" ]; then
            sudo virsh managedsave $vm 2> /dev/null # Do this to each one
        fi
    done < <( printf '%s\n' "${vm_array[@]}")

    sudo shutdown -h +1
    echo "VMs are being put into saved states..."
    echo "Shutting down in 5 minutes..."

elif [[ $1 == "--reboot" ]]; then # Freeze all VMs and reboot the host server
    mapfile -t vm_array < <( sudo virsh list --all --name | tr -s '\n' )
    while read -r vm; do
        if [ ! -z "$vm" ]; then
            sudo virsh managedsave $vm 2> /dev/null # Do this to each one
        fi
    done < <( printf '%s\n' "${vm_array[@]}")

    sudo shutdown -r +5
    echo "VMs are being put into saved states..."
    echo "Restarting in 5 minutes..."

elif [[ $1 == "--sync" ]]; then # Synchronize the system clock of each VM with the RTC (used with cronjob @reboot)
    mapfile -t vm_array < <( sudo virsh list --all --name | tr -s '\n' )
    while read -r vm; do
        PID=$(sudo virsh -c qemu:///system qemu-agent-command $vm "{\"execute\":\"guest-exec\",\"arguments\":{\"path\":\"/sbin/hwclock\",\"arg\":[\"--hctosys\"],\"capture-output\":true}}" 2> /dev/null | cut -d ":" -f 3 | sed 's/}}//')
        finished=0; echo ""; echo "Syncing the \"$vm\" VM instance system clock with the RTC."
        while [[ ${finished} -eq 0 ]]; do
            sleep 1
            STATUS=$(sudo virsh -c qemu:///system qemu-agent-command $vm "{\"execute\":\"guest-exec-status\",\"arguments\":{\"pid\":$PID}}" 2> /dev/null)
            if [[ $(echo $STATUS | jq '.return.exited') == "true" || -z $STATUS ]]; then
                finished=1
                echo -n "Exit Code: "; echo $STATUS | jq '.return.exitcode'; echo ""
            fi
        done
    done < <( printf '%s\n' "${vm_array[@]}")

elif [[ $1 == "--backup" ]]; then # Backup all pertinent VM files to ~/rsbakcup
    mkdir -p ~/rsbackup

    mapfile -t vm_array < <( sudo virsh list --all --name | tr -s '\n' )
    while read -r vm; do
        rsync -caz -e "ssh -i ~/.ssh/vmkey" satoshi@${vm}.local:~/backup/ ~/rsbackup/${vm}/ --delete --copy-links --rsync-path="sudo rsync"
    done < <( printf '%s\n' "${vm_array[@]}")

elif [[ $1 == "--restore" ]]; then # Restore backup files to $VM_NAME @ /home/satoshi/restore; Parameters: $VM_NAME
    VM_NAME=${2}
    rsync -caz -e "ssh -i ~/.ssh/vmkey" ~/rsbackup/${VM_NAME}/ satoshi@${VM_NAME}.local:~/restore

elif [[ $1 == "--delete" ]]; then # Deletes a VM instance; Parameters: $VM_NAME
    sudo virsh destroy ${2}
    sudo virsh managedsave-remove ${2}
    sudo virsh undefine --nvram ${2}
    sudo find -L /var/lib/libvirt/images -name "${2}.qcow2" -type f -delete # Remove VM (Only if it is shutdown)
    echo "vmctl --delete ${2} # $(date)"  >> ~/vm-creation.log # Show the deletion in the VM Creation log

    echo ""; echo "Remember to remove the static IP of the \"${2}\" VM instance (if it has one) in the OPNsense/PFsense router!"
    read -p "Press the enter key to continue..."

else
    $0 --help
    echo "Script Version 0.11"
fi
