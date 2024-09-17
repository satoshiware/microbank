### LVM Storage Management is divided into three parts:
- Physical Volumes (PV) – Actual disks (e.g. /dev/sda, /dev,sdb, /dev/vdb and so on)
- Volume Groups (VG) – Physical volumes are combined into volume groups. (e.g. my_vg = /dev/sda + /dev/sdb.)
- Logical Volumes (LV) – A volume group is divided up into logical volumes (e.g. my_vg divided into my_vg/data, my_vg/backups, my_vg/home, my_vg/mysqldb and so on)

sudo pvs 											                      # See info' about Physical Volumes
sudo pvdisplay 										                  # See detailed attributes about Physical Volumes

sudo vgs											                      # See info' about Volume Groups
sudo vgdisplay										                  # See detailed attributes about Volume Groups

sudo lvs											                      # See info' about Logical Volumes
sudo lvdisplay										                  # See detailed attributes about Logical Volumes

sudo fdisk -l | grep '^Disk /dev/' 					        # See info' about disks
sudo lvmdiskscan									                  # Scan for all devices visible to LVM

#### Commands to extend LVM ####
sudo pvcreate /dev/${DISK}							            # Create LVM Physical Volume
sudo lvmdiskscan -l									                # Verify LVM Physical Volume

sudo vgextend ${VGROUP} /dev/${DISK}				        # Add a Physical Volume ${DISK} to ${VGROUP} Volume Group

sudo lvm lvextend -l +100%FREE /dev/${VGROUP}/root	# Extend the /dev/${VGROUP}/root Volume Group to include all "free" space
sudo resize2fs -p /dev/mapper/${VGROUP//-/--}-root	# Enlarge the filesystem created inside the “root” volume

df -H												                        # Verify disk space has grown
