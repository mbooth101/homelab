#!/bin/bash

# Issue a certificate for a staging host from the self-signed CA created by
# create_ca.sh.
#
# Usage: create_cert.sh <host>

set -e

HOST="$1"
if [ -z "$HOST" ] ; then
	echo "Usage: $0 <host>" >&2
	exit 1
fi
SUBJECT="/CN=$HOST"

DIR="$(readlink -f $(dirname $0))"
DIR_HOST="$DIR/$HOST"
VAULT_PASS="$(readlink -f $DIR/../../../vault_pass)"

# Just a simple unix timestamp
SERIAL="$( date +%s )"

# Install openssl if command not found
if ! which openssl &>/dev/null ; then
	sudo dnf install --assumeyes openssl
fi

if [ ! -d $DIR_HOST ] ; then
	mkdir $DIR_HOST

	# The CA key is vault-encrypted, so it is decrypted into memory only
	# and never written to disk in plain text
	CA_KEY="$(ansible-vault view --vault-password-file "$VAULT_PASS" "$DIR/CA.key" </dev/null)"

	openssl req -new -newkey ec -pkeyopt ec_paramgen_curve:P-256 -noenc \
		-keyout "$DIR_HOST/privkey.pem" -out "$DIR_HOST/cert.csr" -subj "$SUBJECT"
	openssl x509 -req -days 36500 -in $DIR_HOST/cert.csr -CA $DIR/CA.pem -CAkey <(printf '%s\n' "$CA_KEY") \
		-set_serial $SERIAL -out $DIR_HOST/cert.pem \
		-extfile <(cat <<-EOF
			basicConstraints = critical, CA:FALSE
			keyUsage = critical, digitalSignature
			extendedKeyUsage = serverAuth
			subjectAltName = DNS:$HOST
			subjectKeyIdentifier = hash
			authorityKeyIdentifier = keyid
		EOF
		)
	rm $DIR_HOST/cert.csr
	cat $DIR/CA.pem > $DIR_HOST/chain.pem
	cat $DIR_HOST/cert.pem $DIR_HOST/chain.pem > $DIR_HOST/fullchain.pem
fi
