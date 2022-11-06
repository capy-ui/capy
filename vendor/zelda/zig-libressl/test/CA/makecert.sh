#!/bin/sh

usage() {
    echo "usage: makecert.sh [-c] [-d days] [-e email] name"
    echo " "
    echo "name: CN of certficate and name of output file" 
    echo "-d days: number of days cert to be valid for"
    echo "-e email: add email to cert subject"
    echo "-c: make a client cert, default is server"
    echo " "
    echo "script must be run in the CA directory of this tutorial"
    exit 1
}

args=`getopt ce:d: $*`
if [ $? -ne 0 ]
then
    usage
fi

set -- $args
while [ $# -ne 0 ]
do
    case "$1"
    in
        -c)
            cflag="$1"; shift;;
        -e)
            email="$2"; shift; shift;;
        -d)
           days="$2"; shift; shift;;
        --)
            shift; break;;
    esac
done

if [ -z "$1" ]; then
    usage
else
    CN=$1
fi

if [ -z "$email" ]; then
    subject="/C=CA/ST=Edmonton/O=Bob Beck/OU=Certificanator/CN=${CN}"
else
    subject="/emailAddress=${email}/C=CA/ST=Edmonton/O=Bob Beck/OU=Certificanator/CN=${CN}"
fi

if [ -z "$cflag"]; then
    type="server_cert"
else
    type="user_cert"
fi

if [ -z "$days"]; then
    days="375"
fi

keyfile="${CN}.key"
csrfile="${CN},csr"
crtfile="${CN}.crt"

(cd intermediate && openssl genrsa -out private/${keyfile} 2048)
(cd intermediate && openssl req -batch -config openssl.cnf -new -key private/client.key -subj "${subject}" -out csr/$csrfile)
openssl ca -batch -config intermediate/openssl.cnf -extensions ${type} -days ${days} -notext -md sha256 -in intermediate/csr/${csrfile} -out intermediate/certs/${crtfile}
if [ $? -eq 0 ]; then
    cp intermediate/private/${keyfile} ${keyfile}
    cp intermediate/certs/${crtfile} ${crtfile}
else
    echo "openssl ca appears to have been unhappy.. much sadness"
    exit 1
fi
