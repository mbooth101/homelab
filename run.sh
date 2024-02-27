#!/bin/bash

set -e

# Check if running for staging or production
HOSTS=${PROD:+production}
if [ -z "$HOSTS" ] ; then
	HOSTS="staging"
fi

# Give time to change our minds
MSG="Running For \"$HOSTS\" Hosts"
echo
printf '!%.0s' $(seq 1 $((${#MSG} + 8))) ; echo
echo "!!! $MSG !!!"
printf '!%.0s' $(seq 1 $((${#MSG} + 8))) ; echo
echo
if [ "$HOSTS" = "staging" ] ; then
	echo "Hit Ctrl+C and set PROD in the environment to run for production"
elif [ "$HOSTS" = "production" ] ; then
	echo "Hit Ctrl+C and unset PROD in the environment to run for staging"
fi
echo
sleep 3

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
	# Reset keys for hosts that need initialising
	while read h; do
		host=$(echo "$h" | cut -f1 -d' ')
		ssh-keygen -R $host
		ssh-keyscan -H $host >> ~/.ssh/known_hosts
	done <$HOSTS

	# Initial run must prompt for passwords in order to set up public key authentication
	ANSIBLE_SSH_COMMON_ARGS="-o PubkeyAuthentication=no" \
	ansible-playbook -u $USER -k -K \
		--ask-vault-pass -i $HOSTS "$@" playbook.yml
	echo "$HOSTS" >> .initialised
else
	# In subsequent runs we connect as the ansible user using public key authentication
	ansible-playbook \
		--ask-vault-pass -i $HOSTS "$@" playbook.yml
fi
