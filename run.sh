#!/bin/bash

SERVER_HOST=major-clanger.matbooth.co.uk

if [ -n "$INITIAL" ] ; then
	ssh-keygen -R $SERVER_HOST
	ssh-keyscan -H $SERVER_HOST >> ~/.ssh/known_hosts
	ANSIBLE_SSH_COMMON_ARGS="-o PubkeyAuthentication=no" ansible-playbook -u $USER -k -K \
		-i $SERVER_HOST, --tags initial "$@" playbook.yml
else
	ansible-playbook -u ansible-maint \
		-i $SERVER_HOST, --skip-tags initial "$@" playbook.yml
fi
