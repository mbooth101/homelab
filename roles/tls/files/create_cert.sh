#!/bin/bash

set -e

HOST="$1"
DOMAIN="$2"
SUBJECT="/C=GB/ST=South Yorkshire/L=Sheffield/O=Mat Booth Ltd/CN=$HOST.$DOMAIN"

DIR="$(readlink -f $(dirname $0))"
DIR_HOST="$DIR/$HOST"

if [ ! -d $DIR_HOST ] ; then
	mkdir $DIR_HOST
	openssl genrsa -out $DIR_HOST/privkey.pem 4096
	openssl req -new -key $DIR_HOST/privkey.pem -out $DIR_HOST/cert.csr -subj "$SUBJECT"
	openssl x509 -req -days 36500 -in $DIR_HOST/cert.csr -CA $DIR/CA.pem -CAkey $DIR/CA.key \
		-set_serial 01 -out $DIR_HOST/cert.pem
	rm $DIR_HOST/cert.csr
	cat $DIR/CA.pem > $DIR_HOST/chain.pem
	cat $DIR_HOST/cert.pem $DIR_HOST/chain.pem > $DIR_HOST/fullchain.pem
fi
