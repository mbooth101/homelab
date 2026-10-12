#!/bin/bash

# Create the self-signed CA used to issue certificates for the staging
# environment.
#
# Usage: create_ca.sh [domain]   (default: test.matbooth.co.uk)

set -e

DOMAIN="${1:-test.matbooth.co.uk}"
SUBJECT="/O=Mat Booth/CN=$DOMAIN staging CA"

DIR="$(readlink -f $(dirname $0))"
VAULT_PASS="$(readlink -f $DIR/../../../vault_pass)"

# Install openssl if command not found
if ! which openssl &>/dev/null ; then
	sudo dnf install --assumeyes openssl
fi

# Replacing the CA invalidates every certificate it has issued, so never do it
# by accident
if [ -e "$DIR/CA.key" ] || [ -e "$DIR/CA.pem" ] ; then
	echo "$DIR/CA.key or CA.pem already exists, remove them first to replace the CA" >&2
	exit 1
fi

openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -noenc \
	-keyout "$DIR/CA.key" -out "$DIR/CA.pem" -days 36500 -subj "$SUBJECT" \
	-addext "basicConstraints=critical,CA:TRUE,pathlen:0" \
	-addext "keyUsage=critical,keyCertSign,cRLSign" \
	-addext "nameConstraints=critical,permitted;DNS:$DOMAIN"

ansible-vault encrypt --vault-password-file "$VAULT_PASS" "$DIR/CA.key"

openssl x509 -in "$DIR/CA.pem" -noout -subject -dates -ext nameConstraints
