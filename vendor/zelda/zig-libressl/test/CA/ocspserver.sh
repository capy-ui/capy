#!/bin/sh

# Vanna Vanna make me an OCSP server
# DO NOT USE THIS FACING THE INTERNET.
# GOD KILLS A BAG OF KITTENS EVERY TIME SOMEONE EXPOSES THE OPENSSL COMMAND AS ATTACK SURFACE!
# PLEASE THINK OF THE KITTENS

openssl ocsp -port 127.0.0.1:2560 -text -sha256  -index intermediate/index.txt -CA chain.pem -rkey intermediate/private/ocsp-localhost.key.pem -rsigner intermediate/certs/ocsp-localhost.pem

