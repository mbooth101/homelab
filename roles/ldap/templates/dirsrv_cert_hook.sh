#!/bin/bash

/usr/sbin/dsctl {{ ldap_instance }} tls import-server-key-cert \
	/etc/letsencrypt/certs/{{ role_name }}.{{ domain }}/cert.pem \
	/etc/letsencrypt/certs/{{ role_name }}.{{ domain }}/privkey.pem
/usr/sbin/dsconf {{ ldap_instance }} security certificate add \
	--file /etc/letsencrypt/certs/{{ role_name }}.{{ domain }}/cert.pem \
	--primary-cert --name "Server-Cert"
/usr/sbin/dsctl {{ ldap_instance }} restart

