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
		ansible ansible-freeipa \
		python3-netaddr python3-libdnf5 \
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

# Determine if machines have been provisioned already
PROVISION=1
if [ -f .provisioned ] ; then
	while read i; do
		if [ "$i" = "$HOSTS" ] ; then
			PROVISION=
			break
		fi
	done <.provisioned
fi

# Determine if machines have been bootstrapped already
BOOTSTRAP=1
if [ -f .bootstrapped ] ; then
	while read i; do
		if [ "$i" = "$HOSTS" ] ; then
			BOOTSTRAP=
			break
		fi
	done <.bootstrapped
fi

if [ -n "$PROVISION" ] ; then
	while read h; do
		fqdn=$(echo "$h" | cut -f1 -d' ')
		host=$(echo "$fqdn" | cut -f1 -d.)

		# If provisioning staging, then kill and recreate the VM
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
			nic1="address.type=pci,address.domain=0,address.bus=1,address.slot=0"
			nic4="address.type=pci,address.domain=0,address.bus=4,address.slot=0"
			virt-install \
				--connect qemu:///system \
				--autoconsole none \
				--name "$host" \
				--vcpus 2 \
				--memory 4096 \
				--disk size=16 \
				--network network=network,mac=52:54:00:00:00:01,$nic1 \
				--network network=network,mac=52:54:00:00:00:0a,$nic4,address.function=0 \
				--network network=network,mac=52:54:00:00:00:0b,$nic4,address.function=1 \
				--network network=network,mac=52:54:00:00:00:0c,$nic4,address.function=2 \
				--network network=network,mac=52:54:00:00:00:0d,$nic4,address.function=3 \
				--os-variant fedora-unknown \
				--location ${url} \
				--initrd-inject ks-vm.cfg \
				--extra-args "inst.ks=file:/ks-vm.cfg"

			# Wait until VM shuts down following OS installation
			while [ "$(virsh --connect qemu:///system domstate $host)" != "shut off" ] ; do
				sleep 2
			done

			# Restart VM and wait until SSH is up
			virsh --connect qemu:///system start $host
			until nc -z $host 22 ; do
				sleep 1
			done
		else
			echo "TODO provision physical machine"
		fi

		# Reset keys for hosts that need bootstrapping
		ssh-keygen -R $fqdn
		ssh-keyscan -H $fqdn >> ~/.ssh/known_hosts

		# Configure SSH client for newly provisioned hosts
		if ! grep -q '$fqdn' ~/.ssh/config ; then
			echo "Host $fqdn" >> ~/.ssh/config
			echo "  IdentitiesOnly yes" >> ~/.ssh/config
			echo "  IdentityFile ~/.ssh/id_home" >> ~/.ssh/config
			echo "  User ansible-maint" >> ~/.ssh/config
		fi

	done <$HOSTS

	echo "$HOSTS" >> .provisioned
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
		-i $HOSTS --tags "bootstrap" "$@" playbook.yml
	echo "$HOSTS" >> .bootstrapped
else
	# In subsequent runs we connect as the ansible-maint user using public key
	# authentication
	ansible-playbook $VAULT_PASS \
		-i $HOSTS --skip-tags "bootstrap" "$@" playbook.yml
fi

# Update dependecy graph
./depgraph.py
