#!/bin/bash

# Make sure we are not running as root, but that we have sudo privileges.
if [ "$(id -u)" = "0" ]; then
   echo "This script must NOT be run as root (or with sudo)!"
   exit 1
elif [ "$(sudo -l | grep '(ALL : ALL) ALL' | wc -l)" = 0 ]; then
   echo "You do not have enough sudo privileges!"
   exit 1
fi
cd ~; sudo pwd # Print Working Directory; have the user enable sudo access if not already.

# Disable sudo password for this user
echo "$USER ALL=(ALL) NOPASSWD: ALL" | sudo EDITOR='tee -a' visudo

# Give the user pertinent information about this script and how to use it.
cat << EOF | sudo tee ~/readme.txt
This host (server) was configured to run Type 1 VMs using qemu/kvm

Relevant Commands:

#### Host Information CMDs ####
df -h --output=target,size,pcent        # Disk Space Usage
ip address show                         # Network Info (See MAC and IP addresses on devices; see if we are connected via the "bridge")
sudo virt-host-validate qemu            # Verify the configuration can run all libvirt hypervisor drivers. (secure guest support only available on some cpus)
sudo dmesg | grep -i -e DMAR -e IOMMU   # On the Intel CPU, verify that the VT-d is enabled.
sudo dmesg | grep -i -e AMD-Vi          # On the AMD CPU, verify that the AMD-Vi is enabled.
osinfo-query os | grep "debian"         # Get a list of the accepted Debian operating system variant names (--os-variant)
sudo virsh nodeinfo                     # Run the following command to get info for the host machine

#### File Locations ####
/etc/libvirt/qemu                                                       # XML files
/var/lib/libvirt/images                                                 # Qcow2 Images

#### More CMDs ####
sudo virsh list --all                                                   # List all VMs
sudo virsh domifaddr \$VM_NAME --source agent                           # See MAC and IP of VM (only if running)
sudo virsh dominfo \$VM_NAME                                            # General VM information

#### RAM ####
sudo virsh dommemstat --domain \$VM_NAME                                # Memory stat's
sudo virsh setmem --domain \$VM_NAME --size 3G --config                 # Update the memory size (make sure VM is shut off)
sudo virsh setmaxmem --domain \$VM_NAME --size 3G --config              # Update the maximum memory size (make sure VM is shut off)

#### vCPU ####
sudo virsh vcpucount \$VM_NAME                                          # Get vcpu count
sudo virsh vcpuinfo \$VM_NAME                                           # Get detailed domain vcpu information
sudo virsh setvcpus \$VM_NAME <number-of-CPUs> --config                 # Change number of virtual CPUs
sudo virsh setvcpus \$VM_NAME <max-number-of-CPUs> --maximum --config   # Change maximum number of virtual CPUs

#### Disk Space ####
sudo virsh domblkinfo \$VM_NAME -all                                     # Disk Capacity, Allocation, and Physical characteristics
du -h /var/lib/libvirt/images/\${VM_IMAGE}                               # See the actual size of the image file

#### Control ####
sudo virsh console \$VM_NAME                                            # Switch to active VM ("Ctrl + ]" or to exit)
sudo virsh start \$VM_NAME                                              # Start VM from inactive mode
sudo virsh shutdown \$VM_NAME                                           # Shutdown the new instance
sudo virsh reboot \$VM_NAME                                             # Reboot VM instance
sudo virsh reset domain \$VM_NAME                                       # Sends the reset signal (as if the reset button was pressed)
sudo virsh destroy \$VM_NAME --graceful                                 # Force a shutdown (gracefully if possible)
sshvm                                                                   # Alias (with no arguments) for quick ssh connection (after prompt) to any VM

Note: The "vmctl" script was installed. Use this to install new VM instances.
    Execute "vmctl" to learn of its features.
EOF
read -p "Press the enter key to continue..."

#### Update and Upgrade
sudo apt-get -y update  # Update
sudo apt-get -y upgrade # Upgrade

#### Install Packages
sudo apt-get -y install qemu-system-x86         # A user-level KVM emulator that facilitates communication between hosts and VMs. (qemu-kvm/qemu-full)
sudo apt-get -y install libvirt-daemon-system   # A daemon that manages virtual machines and the hypervisor as well as handles library calls. (libvirt)
sudo apt-get -y install virtinst                # A command-line tool for creating guest virtual machines. (virt-install)
sudo apt-get -y install ovmf                    # Enables UEFI support for Virtual Machines. (edk2-ovmf)
sudo apt-get -y install swtpm                   # A TPM emulator for Virtual Machines.
sudo apt-get -y install qemu-utils              # Provides tools to create, convert, modify, and snapshot offline disk images. (qemu-img)
sudo apt-get -y install guestfs-tools           # Provides a set of extended command-line tools for managing virtual machines.
sudo apt-get -y install libosinfo-bin           # A library for managing OS information for virtualization. (libosinfo)
sudo apt-get -y install tuned                   # A system tuning service for Linux.
sudo apt-get -y install jq                      # Command-line JSON processing tool
sudo apt-get -y install rsync                   # Remote (& local) file synchronization tool. The host coordinates the backing up of important files for each instance.

# Disable Password Authentication
sudo sed -i 's/#.*PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config # Disable password login
sudo mkdir -p ~/.ssh
sudo touch ~/.ssh/authorized_keys
sudo chown -R $USER:$USER ~/.ssh
sudo chmod 700 ~/.ssh
sudo chmod 600 ~/.ssh/authorized_keys
read -p "Yubikey Public Key (For Next Login): " YUBIKEY; echo $YUBIKEY | sudo tee -a ~/.ssh/authorized_keys; echo "Key added to ~/.ssh/authorized_keys"

# Generate public/private keys (non-encrytped) for "satoshi"
ssh-keygen -t ed25519 -f /home/satoshi/.ssh/vmkey -N "" -C ""

# Add sshvm script for easy ssh connections to VMs
cat << EOF | sudo tee /usr/local/sbin/sshvm
#!/bin/bash

# Check for any parameter passed
if [[ ! -z \${1} ]]; then
    ssh satoshi@\${1}.local -i ~/.ssh/vmkey
    exit
fi

# Fill directory with all VM names for autocompletion
SSDWEAR=\$((1 + \$RANDOM % 100000)) # Random location to mitigate any possibility of SSD/NVME wear
rm -rf /tmp/vmssh/\$SSDWEAR
mkdir -p /tmp/vmssh/\$SSDWEAR
mapfile -t array < <( sudo virsh list --all | tail --lines=+3 | awk '{print \$2}' )
for vm in "\${array[@]}"; do
    touch /tmp/vmssh/\$SSDWEAR/\$vm
done
cd /tmp/vmssh/\$SSDWEAR

# Show VMs and their statuses
echo ""
sudo virsh list --all

# Get VM of choice from user
echo ""
read -e -p "What vm would you like to connect to? " VM_NAME

# If nothing was entered then exit
if [[ -z \${VM_NAME} ]]; then
    exit
fi

# SSH login via VM number or VM name
if [[ "\$VM_NAME" =~ ^[0-9]+\$ ]]; then
    ssh satoshi@\${array[((\${VM_NAME} - 1))]}.local -i ~/.ssh/vmkey
else
    ssh satoshi@\${VM_NAME}.local -i ~/.ssh/vmkey
fi
EOF
sudo chmod 755 /usr/local/sbin/sshvm

#### Update Grub to configure I/O memory management unit (IOMMU) in pass-through mode (for AMD CPUs, IOMMU is enabled by default)
sudo sed -i "s/GRUB_CMDLINE_LINUX=\"/&intel_iommu=on iommu=pt/" /etc/default/grub
sudo update-grub # Regenerate the grub configuration file

#### Tune the machine for running KVM guests
sudo systemctl enable tuned --now; sleep 5 # Enable and start the TuneD service and wait 5 seconds
sudo tuned-adm profile virtual-host # This optimizes the host for running KVM guests

#### Enable systemd-networkd to manage network and create a bridge (bridge0)
sudo mv /etc/network/interfaces /etc/network/interfaces.save # Move the interfaces file so it won't be used after systemd-networkd is set up
sudo systemctl enable systemd-networkd # Enable systemd-networkd to manage our network

echo ""; ip link show; echo ""; read -p "Creating a bridge (bridge0)... enter the NIC device name (e.g. enp2s0): " eth_device # Get NIC device name
mac_address=$(ip link show ${eth_device} | grep -Eo "([a-fA-F0-9]{2}:){5}[a-fA-F0-9]{2}" | head -n 1)

cat << EOF | sudo tee /etc/systemd/network/bridge0.netdev # Create a bridge (bridge0) with the same MAC address as the physical NIC
  [NetDev]
  Name=bridge0
  Kind=bridge
  MACAddress=${mac_address}
EOF

cat << EOF | sudo tee /etc/systemd/network/bridge0.network # link the new virtual bridge to the physical NIC
  [Match]
  Name=${eth_device}

  [Network]
  Bridge=bridge0
EOF

cat << EOF | sudo tee /etc/systemd/network/lan0.network # Define the network
  [Match]
  Name=bridge0

  [Network]
  DHCP=ipv4
EOF

#### Create a virtual bridge network in KVM (so VMs can use the bridge interface by name)
cat << EOF | sudo tee ~/tmp_nwbridge.xml # Create tmp file with configuration data
<network>
  <name>nwbridge</name>
  <forward mode='bridge'/>
  <bridge name='bridge0'/>
</network>
EOF
sudo virsh net-define ~/tmp_nwbridge.xml # Define nwbridge as a persistent virtual network.
sudo virsh net-start nwbridge # Activate the nwbridge and set it to autostart on boot.
sudo virsh net-autostart nwbridge
sudo rm ~/tmp_nwbridge.xml # Delete the nwbridge.xml file; It’s not required anymore

#### Install vmctl VM control script
echo "PATH=\"/usr/local/sbin:\$PATH\"" | sudo tee -a ~/.profile
bash ~/microbank/scripts/vmctl.sh --install

# Establish aliases for "sudo shutdown [now]" and "sudo reboot [now]"
echo $'alias sudo=\'sudo \'' | sudo tee -a /etc/bash.bashrc
echo $'alias shutdown=\'echo "alias override: use \\"vmctl --shutdown\\""; echo "Manually overide aliases with the \\"\\\\\\" character before the alias cmd."\'' | sudo tee -a /etc/bash.bashrc
echo $'alias reboot=\'echo "alias override: use \\"vmctl --reboot\\""; echo "Manually overide aliases with the \\"\\\\\\" character before the alias cmd."\'' | sudo tee -a /etc/bash.bashrc

#### Download Debian ISO, Set Timezone, & Create Preseeding File
sudo mkdir -p /dc/iso/bookworm; cd /dc/iso
sudo wget https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-12.7.0-amd64-netinst.iso
sudo mv /dc/iso/debian-12.7.0-amd64-netinst.iso /dc/iso/debian-install.iso

# Set the Timezone
echo ""; ls -R -l /usr/share/zoneinfo/US
echo ""; echo "See the \"/usr/share/zoneinfo/\" folder for all the valid time zone names."
read -p "What Is Your Time Zone? (e.g. US/Arizona): " TIMEZONE

# Create preseed.cfg File Function
cat << EOF | sudo tee /dc/iso/preseed.cfg
#Source: https://www.debian.org/releases/bookworm/example-preseed.txt
#_preseed_V1
#### Contents of the preconfiguration file (for bookworm)
### Localization
# Preseeding only locale sets language, country and locale.
d-i debian-installer/locale string en_US

# The values can also be preseeded individually for greater flexibility.
#d-i debian-installer/language string en
#d-i debian-installer/country string NL
#d-i debian-installer/locale string en_GB.UTF-8
# Optionally specify additional locales to be generated.
#d-i localechooser/supported-locales multiselect en_US.UTF-8, nl_NL.UTF-8

# Keyboard selection.
d-i keyboard-configuration/xkb-keymap select us
# d-i keyboard-configuration/toggle select No toggling

### Network configuration
# Disable network configuration entirely. This is useful for cdrom
# installations on non-networked devices where the network questions,
# warning and long timeouts are a nuisance.
#d-i netcfg/enable boolean false

# netcfg will choose an interface that has link if possible. This makes it
# skip displaying a list if there is more than one interface.
d-i netcfg/choose_interface select auto

# To pick a particular interface instead:
#d-i netcfg/choose_interface select eth1

# To set a different link detection timeout (default is 3 seconds).
# Values are interpreted as seconds.
#d-i netcfg/link_wait_timeout string 10

# If you have a slow dhcp server and the installer times out waiting for
# it, this might be useful.
#d-i netcfg/dhcp_timeout string 60
#d-i netcfg/dhcpv6_timeout string 60

# Automatic network configuration is the default.
# If you prefer to configure the network manually, uncomment this line and
# the static network configuration below.
#d-i netcfg/disable_autoconfig boolean true

# If you want the preconfiguration file to work on systems both with and
# without a dhcp server, uncomment these lines and the static network
# configuration below.
#d-i netcfg/dhcp_failed note
#d-i netcfg/dhcp_options select Configure network manually

# Static network configuration.
#
# IPv4 example
#d-i netcfg/get_ipaddress string 192.168.1.42
#d-i netcfg/get_netmask string 255.255.255.0
#d-i netcfg/get_gateway string 192.168.1.1
#d-i netcfg/get_nameservers string 192.168.1.1
#d-i netcfg/confirm_static boolean true
#
# IPv6 example
#d-i netcfg/get_ipaddress string fc00::2
#d-i netcfg/get_netmask string ffff:ffff:ffff:ffff::
#d-i netcfg/get_gateway string fc00::1
#d-i netcfg/get_nameservers string fc00::1
#d-i netcfg/confirm_static boolean true

# Any hostname and domain names assigned from dhcp take precedence over
# values set here. However, setting the values still prevents the questions
# from being shown, even if values come from dhcp.
d-i netcfg/get_hostname string unassigned-hostname
d-i netcfg/get_domain string unassigned-domain

# If you want to force a hostname, regardless of what either the DHCP
# server returns or what the reverse DNS entry for the IP is, uncomment
# and adjust the following line.
#d-i netcfg/hostname string somehost

# Disable that annoying WEP key dialog.
d-i netcfg/wireless_wep string
# The wacky dhcp hostname that some ISPs use as a password of sorts.
#d-i netcfg/dhcp_hostname string radish

# If you want to completely disable firmware lookup (i.e. not use firmware
# files or packages that might be available on installation images):
#d-i hw-detect/firmware-lookup string never

# If non-free firmware is needed for the network or other hardware, you can
# configure the installer to always try to load it, without prompting. Or
# change to false to disable asking.
#d-i hw-detect/load_firmware boolean true

### Network console
# Use the following settings if you wish to make use of the network-console
# component for remote installation over SSH. This only makes sense if you
# intend to perform the remainder of the installation manually.
#d-i anna/choose_modules string network-console
#d-i network-console/authorized_keys_url string http://10.0.0.1/openssh-key
#d-i network-console/password password r00tme
#d-i network-console/password-again password r00tme

### Mirror settings
# Mirror protocol:
# If you select ftp, the mirror/country string does not need to be set.
# Default value for the mirror protocol: http.
#d-i mirror/protocol string ftp
d-i mirror/country string manual
d-i mirror/http/hostname string http.us.debian.org
d-i mirror/http/directory string /debian
d-i mirror/http/proxy string

# Suite to install.
#d-i mirror/suite string testing
# Suite to use for loading installer components (optional).
#d-i mirror/udeb/suite string testing

### Account setup
# Skip creation of a root account (normal user account will be able to
# use sudo).
#d-i passwd/root-login boolean false
# Alternatively, to skip creation of a normal user account.
#d-i passwd/make-user boolean false

# Root password, either in clear text
#d-i passwd/root-password password r00tme
d-i passwd/root-password password
#d-i passwd/root-password-again password r00tme
d-i passwd/root-password-again password
# or encrypted using a crypt(3)  hash.
#d-i passwd/root-password-crypted password [crypt(3) hash]

# To create a normal user account.
#d-i passwd/user-fullname string Debian User
d-i passwd/user-fullname string Satoshi Nakamoto
#d-i passwd/username string debian
d-i passwd/username string satoshi
# Normal user's password, either in clear text
#d-i passwd/user-password password insecure
d-i passwd/user-password password satoshi
#d-i passwd/user-password-again password insecure
d-i passwd/user-password-again password satoshi
# or encrypted using a crypt(3) hash.
#d-i passwd/user-password-crypted password [crypt(3) hash]
# Create the first user with the specified UID instead of the default.
#d-i passwd/user-uid string 1010

# The user account will be added to some standard initial groups. To
# override that, use this.
#d-i passwd/user-default-groups string audio cdrom video

### Clock and time zone setup
# Controls whether or not the hardware clock is set to UTC.
d-i clock-setup/utc boolean true

# You may set this to any valid setting for \$TZ; see the contents of
# /usr/share/zoneinfo/ for valid values.
d-i time/zone string ${TIMEZONE}

# Controls whether to use NTP to set the clock during the install
d-i clock-setup/ntp boolean true
# NTP server to use. The default is almost always fine here.
#d-i clock-setup/ntp-server string ntp.example.com

### Partitioning
## Partitioning example
# If the system has free space you can choose to only partition that space.
# This is only honoured if partman-auto/method (below) is not set.
#d-i partman-auto/init_automatically_partition select biggest_free

# Alternatively, you may specify a disk to partition. If the system has only
# one disk the installer will default to using that, but otherwise the device
# name must be given in traditional, non-devfs format (so e.g. /dev/sda
# and not e.g. /dev/discs/disc0/disc).
# For example, to use the first SCSI/SATA hard disk:
#d-i partman-auto/disk string /dev/sda
# In addition, you'll need to specify the method to use.
# The presently available methods are:
# - regular: use the usual partition types for your architecture
# - lvm:     use LVM to partition the disk
# - crypto:  use LVM within an encrypted partition
d-i partman-auto/method string lvm

# You can define the amount of space that will be used for the LVM volume
# group. It can either be a size with its unit (eg. 20 GB), a percentage of
# free space or the 'max' keyword.
d-i partman-auto-lvm/guided_size string max

# If one of the disks that are going to be automatically partitioned
# contains an old LVM configuration, the user will normally receive a
# warning. This can be preseeded away...
d-i partman-lvm/device_remove_lvm boolean true
# The same applies to pre-existing software RAID array:
d-i partman-md/device_remove_md boolean true
# And the same goes for the confirmation to write the lvm partitions.
d-i partman-lvm/confirm boolean true
d-i partman-lvm/confirm_nooverwrite boolean true

# You can choose one of the three predefined partitioning recipes:
# - atomic: all files in one partition
# - home:   separate /home partition
# - multi:  separate /home, /var, and /tmp partitions
d-i partman-auto/choose_recipe select atomic

# Or provide a recipe of your own...
# If you have a way to get a recipe file into the d-i environment, you can
# just point at it.
#d-i partman-auto/expert_recipe_file string /hd-media/recipe

# If not, you can put an entire recipe into the preconfiguration file in one
# (logical) line. This example creates a small /boot partition, suitable
# swap, and uses the rest of the space for the root partition:
#d-i partman-auto/expert_recipe string                         \\
#      boot-root ::                                            \\
#              40 50 100 ext3                                  \\
#                      \$primary{ } \$bootable{ }                \\
#                      method{ format } format{ }              \\
#                      use_filesystem{ } filesystem{ ext3 }    \\
#                      mountpoint{ /boot }                     \\
#              .                                               \\
#              500 10000 1000000000 ext3                       \\
#                      method{ format } format{ }              \\
#                      use_filesystem{ } filesystem{ ext3 }    \\
#                      mountpoint{ / }                         \\
#              .                                               \\
#              64 512 300% linux-swap                          \\
#                      method{ swap } format{ }                \\
#              .

# The full recipe format is documented in the file partman-auto-recipe.txt
# included in the 'debian-installer' package or available from D-I source
# repository. This also documents how to specify settings such as file
# system labels, volume group names and which physical devices to include
# in a volume group.

## Partitioning for EFI
# If your system needs an EFI partition you could add something like
# this to the recipe above, as the first element in the recipe:
#               538 538 1075 free                              \\
#                      \$iflabel{ gpt }                         \\
#                      \$reusemethod{ }                         \\
#                      method{ efi }                           \\
#                      format{ }                               \\
#               .                                              \\
#
# The fragment above is for the amd64 architecture; the details may be
# different on other architectures. The 'partman-auto' package in the
# D-I source repository may have an example you can follow.

# This makes partman automatically partition without confirmation, provided
# that you told it what to do using one of the methods above.
d-i partman-partitioning/confirm_write_new_label boolean true
d-i partman/choose_partition select finish
d-i partman/confirm boolean true
d-i partman/confirm_nooverwrite boolean true

# Force UEFI booting ('BIOS compatibility' will be lost). Default: false.
#d-i partman-efi/non_efi_system boolean true
# Ensure the partition table is GPT - this is required for EFI
#d-i partman-partitioning/choose_label select gpt
#d-i partman-partitioning/default_label string gpt

# When disk encryption is enabled, skip wiping the partitions beforehand.
#d-i partman-auto-crypto/erase_disks boolean false

## Partitioning using RAID
# The method should be set to "raid".
#d-i partman-auto/method string raid
# Specify the disks to be partitioned. They will all get the same layout,
# so this will only work if the disks are the same size.
#d-i partman-auto/disk string /dev/sda /dev/sdb

# Next you need to specify the physical partitions that will be used.
#d-i partman-auto/expert_recipe string \\
#      multiraid ::                                         \\
#              1000 5000 4000 raid                          \\
#                      \$primary{ } method{ raid }           \\
#              .                                            \\
#              64 512 300% raid                             \\
#                      method{ raid }                       \\
#              .                                            \\
#              500 10000 1000000000 raid                    \\
#                      method{ raid }                       \\
#              .

# Last you need to specify how the previously defined partitions will be
# used in the RAID setup. Remember to use the correct partition numbers
# for logical partitions. RAID levels 0, 1, 5, 6 and 10 are supported;
# devices are separated using "#".
# Parameters are:
# <raidtype> <devcount> <sparecount> <fstype> <mountpoint> \\
#          <devices> <sparedevices>

#d-i partman-auto-raid/recipe string \\
#    1 2 0 ext3 /                    \\
#          /dev/sda1#/dev/sdb1       \\
#    .                               \\
#    1 2 0 swap -                    \\
#          /dev/sda5#/dev/sdb5       \\
#    .                               \\
#    0 2 0 ext3 /home                \\
#          /dev/sda6#/dev/sdb6       \\
#    .

# For additional information see the file partman-auto-raid-recipe.txt
# included in the 'debian-installer' package or available from D-I source
# repository.

# This makes partman automatically partition without confirmation.
d-i partman-md/confirm boolean true
d-i partman-partitioning/confirm_write_new_label boolean true
d-i partman/choose_partition select finish
d-i partman/confirm boolean true
d-i partman/confirm_nooverwrite boolean true

## Controlling how partitions are mounted
# The default is to mount by UUID, but you can also choose "traditional" to
# use traditional device names, or "label" to try filesystem labels before
# falling back to UUIDs.
#d-i partman/mount_style select uuid

### Base system installation
# Configure APT to not install recommended packages by default. Use of this
# option can result in an incomplete system and should only be used by very
# experienced users.
#d-i base-installer/install-recommends boolean false

# The kernel image (meta) package to be installed; "none" can be used if no
# kernel is to be installed.
#d-i base-installer/kernel/image string linux-image-686

### Apt setup
# Choose, if you want to scan additional installation media
# (default: false).
d-i apt-setup/cdrom/set-first boolean false
# You can choose to install non-free firmware.
#d-i apt-setup/non-free-firmware boolean true
# You can choose to install non-free and contrib software.
#d-i apt-setup/non-free boolean true
#d-i apt-setup/contrib boolean true
# Uncomment the following line, if you don't want to have the sources.list
# entry for a DVD/BD installation image active in the installed system
# (entries for netinst or CD images will be disabled anyway, regardless of
# this setting).
#d-i apt-setup/disable-cdrom-entries boolean true
# Uncomment this if you don't want to use a network mirror.
#d-i apt-setup/use_mirror boolean false
# Select which update services to use; define the mirrors to be used.
# Values shown below are the normal defaults.
#d-i apt-setup/services-select multiselect security, updates
#d-i apt-setup/security_host string security.debian.org

# Additional repositories, local[0-9] available
#d-i apt-setup/local0/repository string http://local.server/debian stable main
#d-i apt-setup/local0/comment string local server
# Enable deb-src lines
#d-i apt-setup/local0/source boolean true
# URL to the public key of the local repository; you must provide a key or
# apt will complain about the unauthenticated repository and so the
# sources.list line will be left commented out.
#d-i apt-setup/local0/key string http://local.server/key
# or one can provide it in-line by base64 encoding the contents of the
# key file (with base64 -w0) and specifying it thus:
#d-i apt-setup/local0/key string base64://LS0tLS1CRUdJTiBQR1AgUFVCTElDIEtFWSBCTE9DSy0tLS0tCi4uLgo=
# The content of the key file is checked to see if it appears to be ASCII-armoured.
# If so it will be saved with an ".asc" extension, otherwise it gets a '.gpg' extension.
# "keybox database" format is currently not supported. (see generators/60local in apt-setup's source)

# By default the installer requires that repositories be authenticated
# using a known gpg key. This setting can be used to disable that
# authentication. Warning: Insecure, not recommended.
#d-i debian-installer/allow_unauthenticated boolean true

# Uncomment this to add multiarch configuration for i386
#d-i apt-setup/multiarch string i386


### Package selection
#tasksel tasksel/first multiselect standard, web-server, kde-desktop

# Or choose to not get the tasksel dialog displayed at all (and don't install
# any packages):
#d-i pkgsel/run_tasksel boolean false
d-i pkgsel/run_tasksel boolean false

# Individual additional packages to install
#d-i pkgsel/include string openssh-server build-essential
d-i pkgsel/include string openssh-server
# Whether to upgrade packages after debootstrap.
# Allowed values: none, safe-upgrade, full-upgrade
#d-i pkgsel/upgrade select none

# You can choose, if your system will report back on what software you have
# installed, and what software you use. The default is not to report back,
# but sending reports helps the project determine what software is most
# popular and should be included on the first CD/DVD.
popularity-contest popularity-contest/participate boolean false

### Boot loader installation
# Grub is the boot loader (for x86).

# This is fairly safe to set, it makes grub install automatically to the UEFI
# partition/boot record if no other operating system is detected on the machine.
d-i grub-installer/only_debian boolean true

# This one makes grub-installer install to the UEFI partition/boot record, if
# it also finds some other OS, which is less safe as it might not be able to
# boot that other OS.
d-i grub-installer/with_other_os boolean true

# Due notably to potential USB sticks, the location of the primary drive can
# not be determined safely in general, so this needs to be specified:
#d-i grub-installer/bootdev  string /dev/sda
# To install to the primary device (assuming it is not a USB stick):
#d-i grub-installer/bootdev  string default

# Alternatively, if you want to install to a location other than the UEFI
# parition/boot record, uncomment and edit these lines:
#d-i grub-installer/only_debian boolean false
#d-i grub-installer/with_other_os boolean false
#d-i grub-installer/bootdev  string (hd0,1)
# To install grub to multiple disks:
#d-i grub-installer/bootdev  string (hd0,1) (hd1,1) (hd2,1)

# Optional password for grub, either in clear text
#d-i grub-installer/password password r00tme
#d-i grub-installer/password-again password r00tme
# or encrypted using an MD5 hash, see grub-md5-crypt(8).
#d-i grub-installer/password-crypted password [MD5 hash]

# Use the following option to add additional boot parameters for the
# installed system (if supported by the bootloader installer).
# Note: options passed to the installer will be added automatically.
#d-i debian-installer/add-kernel-opts string nousb

### Finishing up the installation
# During installations from serial console, the regular virtual consoles
# (VT1-VT6) are normally disabled in /etc/inittab. Uncomment the next
# line to prevent this.
#d-i finish-install/keep-consoles boolean true

# Avoid that last message about the install being complete.
d-i finish-install/reboot_in_progress note

# This will prevent the installer from ejecting the CD during the reboot,
# which is useful in some situations.
#d-i cdrom-detect/eject boolean false

# This is how to make the installer shutdown when finished, but not
# reboot into the installed system.
#d-i debian-installer/exit/halt boolean true
# This will power off the machine instead of just halting it.
#d-i debian-installer/exit/poweroff boolean true

### Preseeding other packages
# Depending on what software you choose to install, or if things go wrong
# during the installation process, it's possible that other questions may
# be asked. You can preseed those too, of course. To get a list of every
# possible question that could be asked during an install, do an
# installation, and then run these commands:
#   debconf-get-selections --installer > file
#   debconf-get-selections >> file


#### Advanced options
### Running custom commands during the installation
# d-i preseeding is inherently not secure. Nothing in the installer checks
# for attempts at buffer overflows or other exploits of the values of a
# preconfiguration file like this one. Only use preconfiguration files from
# trusted locations! To drive that home, and because it's generally useful,
# here's a way to run any shell command you'd like inside the installer,
# automatically.

# This first command is run as early as possible, just after
# preseeding is read.
#d-i preseed/early_command string anna-install some-udeb
# This command is run immediately before the partitioner starts. It may be
# useful to apply dynamic partitioner preseeding that depends on the state
# of the disks (which may not be visible when preseed/early_command runs).
#d-i partman/early_command string debconf-set partman-auto/disk "\$(list-devices disk | head -n1)"
# This command is run just before the install finishes, but when there is
# still a usable /target directory. You can chroot to /target and use it
# directly, or use the apt-install and in-target commands to easily install
# packages and run commands in the target system.
#d-i preseed/late_command string apt-install zsh; in-target chsh -s /bin/zsh
EOF

#### Enable virtualization daemon and restart (and exit)
sudo systemctl enable libvirtd
echo "Rebooting..."; sleep 3; sudo reboot now
exit 0