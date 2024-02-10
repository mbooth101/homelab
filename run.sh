#!/bin/bash

if [ -n "$INITIAL" ] ; then
	ANSIBLE_SSH_COMMON_ARGS="-o PubkeyAuthentication=no" ansible-playbook -u $USER -k -K -i hosts --tags initial "$@" playbook.yml
else
	ansible-playbook -u ansible-maint -i hosts --skip-tags initial "$@" playbook.yml
fi
