#!/bin/bash

set -e

# Check if running for staging or production
HOSTS=${PROD:+production}
if [ -z "$HOSTS" ] ; then
	HOSTS="staging"
fi

# Install deps
if [ -z "$(rpm -qa --qf "%{NAME}\n" | grep '^ansible$')" ] ; then
	sudo dnf install \
		ansible python3-netaddr python3-libdnf5 \
		virt-manager virt-install virt-viewer libvirt-client
fi

# Give time to change our minds
MSG="Running For \"$HOSTS\" Hosts"
echo
printf '!%.0s' $(seq 1 $((${#MSG} + 8))) ; echo
echo "!!! $MSG !!!"
printf '!%.0s' $(seq 1 $((${#MSG} + 8))) ; echo
echo
if [ "$HOSTS" = "staging" ] ; then
	echo -n "Hit Ctrl+C and set PROD in the environment to run for production"
elif [ "$HOSTS" = "production" ] ; then
	echo -n "Hit Ctrl+C and unset PROD in the environment to run for staging"
fi
sleep 1 ; echo -n "."
sleep 1 ; echo -n "."
sleep 1 ; echo -n "."
sleep 1 ; echo ; echo

# Determine if this inventory has been initialised already
INITIAL=1
if [ -f .initialised ] ; then
	while read i; do
		if [ "$i" = "$HOSTS" ] ; then
			INITIAL=
			break
		fi
	done <.initialised
fi

if [ -n "$INITIAL" ] ; then
	while read h; do
		fqdn=$(echo "$h" | cut -f1 -d' ')
		host=$(echo "$fqdn" | cut -f1 -d.)

		# If initial run on staging, then kill and recreate the VM
		if [ "$HOSTS" == "staging" ] ; then

			# Remove old staging VM
			if [ -n "$(virsh --connect qemu:///system list --all --name | grep $host)" ] ; then
				if [ "$(virsh --connect qemu:///system domstate $host)" != "shut off" ] ; then
					virsh --connect qemu:///system destroy --graceful --domain $host
				fi
				virsh --connect qemu:///system undefine --remove-all-storage --domain $host
			fi

			# Recreate staging VM and install OS
			echo "Running virt-install"
			release=41
			url="https://download.fedoraproject.org/pub/fedora/linux/releases/${release}/Everything/x86_64/os/"
			nic="address.type=pci,address.domain=0,address.bus=8,address.slot=0"
			virt-install \
				--connect qemu:///system \
				--autoconsole none \
				--name "$host" \
				--vcpus 2 \
				--memory 4096 \
				--disk size=16 \
				--network network=default,mac=52:54:00:00:00:01 \
				--network network=default,mac=52:54:00:00:00:0a,$nic,address.function=0 \
				--network network=default,mac=52:54:00:00:00:0b,$nic,address.function=1 \
				--network network=default,mac=52:54:00:00:00:0c,$nic,address.function=2 \
				--network network=default,mac=52:54:00:00:00:0d,$nic,address.function=3 \
				--os-variant fedora-unknown \
				--location ${url} \
				--initrd-inject ks.cfg \
				--extra-args "inst.ks=file:/ks.cfg"

			# Wait until VM shuts down following OS installation
			while [ "$(virsh --connect qemu:///system domstate $host)" != "shut off" ] ; do
				sleep 2
			done

			# Restart VM and wait until SSH is up
			virsh --connect qemu:///system start $host
			until nc -z $host 22 ; do
				sleep 1
			done
		fi

		# Reset keys for hosts that need initialising
		ssh-keygen -R $fqdn
		ssh-keyscan -H $fqdn >> ~/.ssh/known_hosts
	done <$HOSTS

	# Initial run must prompt for passwords and connect as root in order to set up
	# public key authentication for the ansible user and disable the root account
	ANSIBLE_SSH_COMMON_ARGS="-o PubkeyAuthentication=no" \
	ansible-playbook -u root -k -K \
		--ask-vault-pass -i $HOSTS "$@" playbook.yml
	echo "$HOSTS" >> .initialised
else
	# In subsequent runs we connect as the ansible user using public key authentication
	ansible-playbook \
		--ask-vault-pass -i $HOSTS "$@" playbook.yml
fi
