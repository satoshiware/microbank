### Creating a Software RAID array 
#### List All Drives
```
lsblk
```

#### Install mdadm utility to manage and monitor software RAID
###### Note: This may already be installed with the base_setup.sh script
```
sudo apt-get -y install mdadm
```

#### Remove existing raid partitions
```
sudo mdadm --zero-superblock /dev/$DISK1 /dev/$DISK2 ... /dev/$DISKn
```
#### If zeroing did not work, clear partitions with wipefs
###### Note: If the kernel did not update, may need to restart before continuing
```
sudo wipefs -a -f /dev/$DISK1
sudo wipefs -a -f /dev/$DISK2
	|	|
sudo wipefs -a -f /dev/$DISKn
```

#### Create Level 5 (Striping /w Distributed Parity) RAID partition $MD (e.g. md0)
```
sudo mdadm --create /dev/$MD --level=5 --raid-devices=n /dev/$DISK1 /dev/$DISK2 ... /dev/$DISKn
```

#### Create ext4 filesystem (i.e. ext4) on $MD block device
```
sudo mkfs.ext4 /dev/$MD
```

#### Mount the RAID Array
```
sudo mkdir /mnt/$MD
sudo mount /dev/$MD /mnt/$MD
```

#### Configure Automatic Mounting 
###### If this is not a fresh install, make sure the fstab file does not contain dublicates or obselete mounts.
```
echo "/dev/$MD /mnt/$MD ext4 defaults,nofail,discard 0 0" | sudo tee -a /etc/fstab
```

#### Ensure RAID configuration persists after a reboot
###### Note: This will also copy all previous raid configuration... Edit the mdadm.conf file to remove duplicate and obselete RAID arrays followed with the CMD "sudo update-initramfs -u" and a reboot if necessary.
```
sudo mdadm --detail --scan | sudo tee -a /etc/mdadm/mdadm.conf
sudo update-initramfs -u
```

#### Create VM image directory in new RAID drive
```
sudo mkdir -p /mnt/$MD/vm_images
sudo chmod 711 /mnt/$MD/vm_images
```

#### Create a link in the VM image directory
```
sudo ln -s /mnt/$MD/vm_images /var/lib/libvirt/images/$LNK_NAME
```

#### Command to query the RAID array
```
sudo mdadm --query --detail /dev/$MD
```
