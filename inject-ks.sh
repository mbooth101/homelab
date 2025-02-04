#!/bin/bash

# Injects a kickstart file into a boot ISO so we can provision
# real hardware without needing PXE boot infrastructure

set -e

ISO=Fedora-Everything-netinst-x86_64-41-1.4.iso
VID=$(isoinfo -d -i $ISO | grep -i "Volume id:" | cut -d' ' -f1,2 --complement)

# Inject kickstart into the root of the iso9660 filesystem
rm -f /tmp/boot.iso && xorriso \
	-indev $ISO -outdev /tmp/boot.iso \
	-map ks-hw.cfg /ks-hw.cfg \
	-boot_image any replay

# Write the image to USB stick
sudo umount /run/media/mbooth/$VID || :
sudo dd if=/tmp/boot.iso of=/dev/sdb bs=8M status=progress oflag=direct

# Edit grub configuration
mkdir -p /tmp/anaconda && sudo mount /dev/sdb2 /tmp/anaconda
sudo sed -i \
	-e "/^set default/s/1/0/" -e "/^set timeout/s/60/3/" \
	-e "/^menuentry 'Install/,+3s/quiet$/inst.ks=hd:LABEL=$VID:\/ks-hw.cfg fbcon=rotate:1/" /tmp/anaconda/EFI/BOOT/{BOOT.conf,grub.cfg}
sudo umount /tmp/anaconda && rmdir /tmp/anaconda
