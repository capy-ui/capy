@echo off
setlocal enabledelayedexpansion
REM	testdsa.bat


REM # Test DSA certificate generation of openssl

set openssl_bin=%1
set openssl_bin=%openssl_bin:/=\%
if not exist %openssl_bin% exit /b 1

REM # Generate DSA paramter set
%openssl_bin% dsaparam 512 -out dsa512.pem
if !errorlevel! neq 0 (
	exit /b 1
)


REM # Generate a DSA certificate
%openssl_bin% req -config %srcdir%\openssl.cnf -x509 -newkey dsa:dsa512.pem -out testdsa.pem -keyout testdsa.key
if !errorlevel! neq 0 (
	exit /b 1
)


REM # Now check the certificate
%openssl_bin% x509 -text -in testdsa.pem
if !errorlevel! neq 0 (
	exit /b 1
)

del testdsa.key dsa512.pem testdsa.pem

exit /b 0
endlocal
