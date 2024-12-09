#!/bin/bash

# Generate an Ansible vault encrypted random password, and output it as
# an Ansible variable with the given name

VAR_NAME="my_password"
if [ -n "$1" ] ; then
	VAR_NAME="$1"
fi

PASS=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)
ansible-vault encrypt_string --vault-password-file vault_pass "$PASS" --name "$VAR_NAME"
