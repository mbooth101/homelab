#!/bin/bash

# Create a self-signed CA certificate for testing/staging

openssl genrsa -out CA.key 4096
openssl req -x509 -new -nodes -key CA.key -sha256 -days 36500 -out CA.pem
