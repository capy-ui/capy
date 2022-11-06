#!/bin/sh

cert=$1
chain=chain.pem
out=${1}-ocsp.der

serial=`openssl x509 -noout -serial -in ${cert} | sed 's/serial=//'`
ocsp_uri=`openssl x509 -noout -ocsp_uri -in ${cert}`
ocsp_host=`echo ${ocsp_uri} | sed '-e s#http://##' -e 's#[:/].*##'`
openssl ocsp -out /dev/null -no_nonce -issuer ${chain} -VAfile ${chain} -header Host ${ocsp_host} -url ${ocsp_uri} -serial 0x${serial} -respout ${out}.new >/dev/null 2>&1
openssl ocsp -out /dev/null -no_nonce -VAfile ${chain} -issuer ${chain} -serial 0x${serial} -respin ${out}.new >/dev/null 2>&1
if [ $? == 0 ]; then
    if [ -r "${out}" ]; then
	mv ${out} ${out}.old
    fi
    mv ${out}.new ${out}
fi
