@echo off
setlocal enabledelayedexpansion
REM	testrsa.bat


REM # Test RSA certificate generation of openssl

set openssl_bin=%1
set openssl_bin=%openssl_bin:/=\%
if not exist %openssl_bin% exit /b 1

REM # Generate RSA private key
%openssl_bin% genrsa -out rsakey.pem
if !errorlevel! neq 0 (
	exit /b 1
)


REM # Generate an RSA certificate
%openssl_bin% req -config %srcdir%\openssl.cnf -key rsakey.pem -new -x509 -days 365 -out rsacert.pem
if !errorlevel! neq 0 (
	exit /b 1
)


REM # Now check the certificate
%openssl_bin% x509 -text -in rsacert.pem
if !errorlevel! neq 0 (
	exit /b 1
)

del rsacert.pem rsakey.pem

exit /b 0
endlocal
