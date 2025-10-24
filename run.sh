#!/bin/bash

set -e

# Check if running for staging or production
DEPLOYMENT_ENV=${PROD:+production}
if [ -z "$DEPLOYMENT_ENV" ] ; then
	DEPLOYMENT_ENV="staging"
fi

# Install deps
if [ -z "$(rpm -qa --qf "%{NAME}\n" | grep '^ansible$')" ] ; then
	sudo dnf install \
		ansible ansible-freeipa openssl \
		python3-netaddr python3-libdnf5 python3-graphviz \
		virt-manager virt-install virt-viewer libvirt-client
fi

# Give time to change our minds
MSG="Running for \"$DEPLOYMENT_ENV\" hosts"
echo
printf '!%.0s' $(seq 1 $((${#MSG} + 8))) ; echo
echo "!!! $MSG !!!"
printf '!%.0s' $(seq 1 $((${#MSG} + 8))) ; echo
echo
if [ "$DEPLOYMENT_ENV" = "staging" ] ; then
	echo -n "Hit Ctrl+C and set PROD in the environment to run for production"
elif [ "$DEPLOYMENT_ENV" = "production" ] ; then
	echo -n "Hit Ctrl+C and unset PROD in the environment to run for staging"
fi
sleep 1 ; echo -n "."
sleep 1 ; echo -n "."
sleep 1 ; echo -n "."
sleep 1 ; echo ; echo

# Determine if machines have been provisioned already, PROVISION will be unset if so
PROVISION=1
if [ -f .provisioned ] ; then
	while read i; do
		if [ "$i" = "$DEPLOYMENT_ENV" ] ; then
			PROVISION=
			break
		fi
	done <.provisioned
fi

# Determine if machines have been bootstrapped already, BOOTSTRAP will be unset if so
BOOTSTRAP=1
if [ -f .bootstrapped ] ; then
	while read i; do
		if [ "$i" = "$DEPLOYMENT_ENV" ] ; then
			BOOTSTRAP=
			break
		fi
	done <.bootstrapped
fi

# Provisioning is requested
if [ -n "$PROVISION" ] ; then
	while read -u 7 h; do
		fqdn=$(echo "$h" | cut -f1 -d' ')
		host=$(echo "$fqdn" | cut -f1 -d.)
		ip=$(echo "$h" | sed -e 's/.*inventory_host4=\([0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+\).*$/\1/')
		gw=$(echo "$ip" | cut -f1,2,3 -d.).1
		rootpw=$(<connection_pass)
		release=43
		url="https://fedora.mirrorservice.org/fedora/linux/development/${release}/Everything/x86_64/os/"

		# If provisioning staging, then kill and recreate the VM
		if [ "$DEPLOYMENT_ENV" == "staging" ] ; then
			# Interpolate kickstart file
			sed -e "s/@ROOTPW@/$rootpw/" -e "s/@LUKSPW@/$rootpw/" -e "s/@NVME0@/vda/" -e "s/@NVME1@/vdb/" \
			    -e "s/@HOSTNAME@/$host/" -e "s/@IPADDR@/$ip/" -e "s/@GATEWAY@/$gw/g" \
			    -e "s/@ROTATE@/0/" -e "s|@URL@|$url|" ks.cfg > /tmp/ks.cfg

			# Create virtual network if not exists
			if ! virsh --connect=qemu:///system net-list --all --name | grep -q homelab ; then
				virsh --connect=qemu:///system net-define $(pwd)/homelab-virtual-network.xml
				virsh --connect=qemu:///system net-autostart homelab
				virsh --connect=qemu:///system net-start homelab
			fi

			# Remove old staging VM
			if virsh --connect qemu:///system list --all --name | grep -q $host ; then
				if [ "$(virsh --connect qemu:///system domstate $host)" != "shut off" ] ; then
					virsh --connect qemu:///system destroy --graceful --domain $host
				fi
				virsh --connect qemu:///system undefine --remove-all-storage --nvram --domain $host
			fi

			# Recreate staging VM and install OS
			echo "Running virt-install"
			virt-install \
				--connect qemu:///system \
				--autoconsole none \
				--name "$host" \
				--vcpus 2 \
				--memory 8192 \
				--boot uefi \
				--disk /var/lib/libvirt/images/$host-nvme0.qcow2,size=16,target.dev=vda,target.bus=virtio,serial=nvme0000 \
				--disk /var/lib/libvirt/images/$host-nvme1.qcow2,size=16,target.dev=vdb,target.bus=virtio,serial=nvme0001 \
				--disk /var/lib/libvirt/images/$host-sda.qcow2,size=5,target.dev=sda,target.bus=sata \
				--disk /var/lib/libvirt/images/$host-sdb.qcow2,size=5,target.dev=sdb,target.bus=sata \
				--disk /var/lib/libvirt/images/$host-sdc.qcow2,size=5,target.dev=sdc,target.bus=sata \
				--disk /var/lib/libvirt/images/$host-sdd.qcow2,size=5,target.dev=sdd,target.bus=sata \
				--network network=homelab,mac=52:54:00:00:00:01,address.type=pci,address.domain=0,address.bus=2,address.slot=0 \
				--network network=homelab,mac=52:54:00:00:00:0a,address.type=pci,address.domain=0,address.bus=4,address.slot=0,address.function=0 \
				--network network=homelab,mac=52:54:00:00:00:0b,address.type=pci,address.domain=0,address.bus=4,address.slot=0,address.function=1 \
				--network network=homelab,mac=52:54:00:00:00:0c,address.type=pci,address.domain=0,address.bus=4,address.slot=0,address.function=2 \
				--network network=homelab,mac=52:54:00:00:00:0d,address.type=pci,address.domain=0,address.bus=4,address.slot=0,address.function=3 \
				--os-variant fedora-unknown \
				--location ${url} \
				--initrd-inject /tmp/ks.cfg \
				--extra-args "inst.ks=file:/ks.cfg"

			# Wait until VM shuts down following OS installation then restart it
			while [ "$(virsh --connect qemu:///system domstate $host)" != "shut off" ] ; do
				sleep 2
			done
			virsh --connect qemu:///system start $host

		# If provisioning production, then generate boot ISO on USB stick
		else
			# Interpolate kickstart file
			sed -e "s/@ROOTPW@/$rootpw/" -e "s/@LUKSPW@/$rootpw/" -e "s/@NVME0@/nvme0n1/" -e "s/@NVME1@/nvme1n1/" \
			    -e "s/@HOSTNAME@/$host/" -e "s/@IPADDR@/$ip/" -e "s/@GATEWAY@/$gw/g" \
			    -e "s/@ROTATE@/1/" -e "s|@URL@|$url|" ks.cfg > /tmp/ks.cfg

			# Find USB stick
			until mount | grep -q iso9660 ; do
				read -n1 -s -r -p $'Insert USB stick then press any key to continue\n' key
			done
			usb_dev=$(mount | grep iso9660 | cut -d' ' -f1 | sed -e 's/[0-9]$//')
			usb_mnt=$(mount | grep iso9660 | cut -d' ' -f3)

			# Find ISO image and inject kickstart into the root of the iso9660 filesystem
			iso=$(ls -1 *.iso | head -n1)
			vol_id=$(isoinfo -d -i $iso | grep -i "Volume id:" | cut -d' ' -f1,2 --complement)
			rm -f /tmp/boot.iso && xorriso \
				-indev $iso -outdev /tmp/boot.iso \
				-map /tmp/ks.cfg /ks.cfg \
				-boot_image any replay

			# Write the image to USB stick
			sudo umount $usb_mnt || :
			sudo dd if=/tmp/boot.iso of=$usb_dev bs=8M status=progress oflag=direct

			# Edit grub configuration
			mkdir -p /tmp/anaconda && sudo mount ${usb_dev}2 /tmp/anaconda
			sudo sed -i \
				-e "/^set default/s/1/0/" -e "/^set timeout/s/60/3/" \
				-e "/^menuentry 'Install/,+3s/quiet$/inst.ks=hd:LABEL=$vol_id:\/ks.cfg fbcon=rotate:1/" /tmp/anaconda/EFI/BOOT/{BOOT.conf,grub.cfg}
			sudo umount /tmp/anaconda && rmdir /tmp/anaconda

			# Wait for OS installation
			read -n1 -s -r -p $'Install production from USB stick then any key to continue\n' key
		fi

		# Wait until SSH is up on provisioned machine
		echo "Waiting for SSH service to come up on provisioned machine..."
		until nc -z $ip 22 ; do
			sleep 5
		done

		# Configure SSH client for newly provisioned hosts
		if ! grep -q "Host $fqdn" ~/.ssh/config ; then
			echo "Host $fqdn" >> ~/.ssh/config
			echo "  IdentitiesOnly yes" >> ~/.ssh/config
			echo "  IdentityFile ~/.ssh/id_home" >> ~/.ssh/config
			echo "  User ansible-maint" >> ~/.ssh/config
		fi

		# Reset keys for newly provisioned hosts
		ssh-keygen -R $fqdn
		ssh-keyscan -t "ecdsa,ed25519,rsa" -H $fqdn >> ~/.ssh/known_hosts

	done 7<<<"$(cat $DEPLOYMENT_ENV)"

	echo "$DEPLOYMENT_ENV" >> .provisioned
fi

# If password files not present, just ask
VAULT_PASS="--ask-vault-pass"
if [ -f "vault_pass" ] ; then
	VAULT_PASS="--vault-password-file vault_pass"
fi
CONN_PASS="--ask-pass"
if [ -f "connection_pass" ] ; then
	CONN_PASS="--connection-password-file connection_pass"
fi

if [ -n "$BOOTSTRAP" ] ; then
	# Initial run must connect as root and use password authentication in order to set up
	# public key authentication for the ansible-maint user and disable the root account
	ansible-playbook $VAULT_PASS -u root $CONN_PASS \
		-i $DEPLOYMENT_ENV --tags "bootstrap" "$@" playbook.yml
	echo "$DEPLOYMENT_ENV" >> .bootstrapped
else
	# In subsequent runs we connect as the ansible-maint user using public key
	# authentication
	ansible-playbook $VAULT_PASS \
		-i $DEPLOYMENT_ENV --skip-tags "bootstrap" "$@" playbook.yml
fi

# Update dependecy graph
./depgraph.py
