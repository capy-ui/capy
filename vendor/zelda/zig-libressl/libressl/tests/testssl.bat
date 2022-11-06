@echo off
setlocal enabledelayedexpansion
REM	testssl.bat

set key=%1
set cert=%2
set CA=-CAfile %3
set ssltest=%4 -key %key% -cert %cert% -c_key %key% -c_cert %cert%
set openssl=%5
set extra=%6

%openssl% version & if !errorlevel! neq 0 exit /b 1

set lines=0
for /f "usebackq" %%s in (`%openssl% x509 -in %cert% -text -noout ^| find "DSA Public Key"`) do (
  set /a lines=%lines%+1
)
if %lines% gtr 0 (
  set dsa_cert=YES
) else (
  set dsa_cert=NO
)

REM #########################################################################

echo test sslv2/sslv3
%ssltest% %extra% & if !errorlevel! neq 0 exit /b 1

echo test sslv2/sslv3 with server authentication
%ssltest% -server_auth %CA% %extra% & if !errorlevel! neq 0 exit /b 1

echo test sslv2/sslv3 with client authentication
%ssltest% -client_auth %CA% %extra% & if !errorlevel! neq 0 exit /b 1

echo test sslv2/sslv3 with both client and server authentication
%ssltest% -server_auth -client_auth %CA% %extra% & if !errorlevel! neq 0 exit /b 1

echo test sslv2/sslv3 via BIO pair
%ssltest% %extra% & if !errorlevel! neq 0 exit /b 1

if %dsa_cert%==NO (
  echo "test sslv2/sslv3 w/o (EC)DHE via BIO pair"
  %ssltest% -bio_pair -no_dhe -no_ecdhe %extra% & if !errorlevel! neq 0 exit /b 1
)

echo test sslv2/sslv3 with 1024bit DHE via BIO pair
%ssltest% -bio_pair -dhe1024dsa -v %extra% & if !errorlevel! neq 0 exit /b 1

echo test sslv2/sslv3 with server authentication
%ssltest% -bio_pair -server_auth %CA% %extra% & if !errorlevel! neq 0 exit /b 1

echo test sslv2/sslv3 with client authentication via BIO pair
%ssltest% -bio_pair -client_auth %CA% %extra% & if !errorlevel! neq 0 exit /b 1

echo test sslv2/sslv3 with both client and server authentication via BIO pair
%ssltest% -bio_pair -server_auth -client_auth %CA% %extra% & if !errorlevel! neq 0 exit /b 1

echo test sslv2/sslv3 with both client and server authentication via BIO pair and app verify
%ssltest% -bio_pair -server_auth -client_auth -app_verify %CA% %extra% & if !errorlevel! neq 0 exit /b 1

echo "Testing ciphersuites"
for %%p in ( SSLv3,TLSv1.2 ) do (
  echo "Testing ciphersuites for %%p"
  for /f "usebackq" %%c in (`%openssl% ciphers -v "%%p+aRSA" ^| find "%%p"`) do (
    echo "Testing %%c"
    %ssltest% -cipher %%c -tls1_2
    if !errorlevel! neq 0 (
      echo "Failed %%c"
      exit /b 1
    )
  )
)
for %%p in ( TLSv1.3 ) do (
  echo "Testing ciphersuites for %%p"
  for /f "usebackq" %%c in (`%openssl% ciphers -v "%%p" ^| find "%%p"`) do (
    echo "Testing %%c"
    %ssltest% -cipher %%c
    if !errorlevel! neq 0 (
      echo "Failed %%c"
      exit /b 1
    )
  )
)

REM ##########################################################################

for /f "usebackq" %%s in (`%openssl% no-dh`) do set nodh=%%s
if %nodh%==no-dh (
  echo skipping anonymous DH tests
) else (
  echo test tls1 with 1024bit anonymous DH, multiple handshakes
  %ssltest% -v -bio_pair -tls1 -cipher ADH -dhe1024dsa -num 10 -f -time %extra% & if !errorlevel! neq 0 exit /b 1
)

REM #for /f "usebackq" %%s in (`%openssl% no-rsa`) do set norsa=%%s
REM #if %norsa%==no-rsa (
REM #  echo skipping RSA tests
REM #) else (
REM #  echo "test tls1 with 1024bit RSA, no (EC)DHE, multiple handshakes"
REM #  %ssltest% -v -bio_pair -tls1 -cert ..\apps\server2.pem -no_dhe -no_ecdhe -num 10 -f -time %extra% & if !errorlevel! neq 0 exit /b 1
REM #
REM #  for /f "usebackq" %%s in (`%openssl% no-dh`) do set nodh=%%s
REM #  if %nodh%==no-dh (
REM #    echo skipping RSA+DHE tests
REM #  ) else (
REM #    echo test tls1 with 1024bit RSA, 1024bit DHE, multiple handshakes
REM #    %ssltest% -v -bio_pair -tls1 -cert ..\apps\server2.pem -dhe1024dsa -num 10 -f -time %extra% & if !errorlevel! neq 0 exit /b 1
REM #  )
REM #)

REM #
REM # DTLS tests
REM #

echo test dtlsv1
%ssltest% -dtls1 %extra% & if !errorlevel! neq 0 exit /b 1

echo test dtlsv1 with server authentication
%ssltest% -dtls1 -server_auth %CA% %extra% & if !errorlevel! neq 0 exit /b 1

echo test dtlsv1 with client authentication
%ssltest% -dtls1 -client_auth %CA% %extra% & if !errorlevel! neq 0 exit /b 1

echo test dtlsv1 with both client and server authentication
%ssltest% -dtls1 -server_auth -client_auth %CA% %extra% & if !errorlevel! neq 0 exit /b 1

echo "Testing DTLS ciphersuites"
for %%p in ( SSLv3 ) do (
  echo "Testing ciphersuites for %%p"
  for /f "usebackq" %%c in (`%openssl% ciphers -v "RSA+%%p:-RC4" ^| find "%%p"`) do (
    echo "Testing %%c"
    %ssltest% -cipher %%c -dtls1
    if !errorlevel! neq 0 (
      echo "Failed %%c"
      exit /b 1
    )
  )
)

REM #
REM # ALPN tests
REM #
echo "Testing ALPN..."
%ssltest% -bio_pair -tls1 -alpn_client foo -alpn_server bar & if !errorlevel! neq 0 exit /b 1
%ssltest% -bio_pair -tls1 -alpn_client foo -alpn_server foo ^
  -alpn_expected foo & if !errorlevel! neq 0 exit /b 1
%ssltest% -bio_pair -tls1 -alpn_client foo,bar -alpn_server foo ^
  -alpn_expected foo & if !errorlevel! neq 0 exit /b 1
%ssltest% -bio_pair -tls1 -alpn_client bar,foo -alpn_server foo ^
  -alpn_expected foo & if !errorlevel! neq 0 exit /b 1
%ssltest% -bio_pair -tls1 -alpn_client bar,foo -alpn_server foo,bar ^
  -alpn_expected foo & if !errorlevel! neq 0 exit /b 1
%ssltest% -bio_pair -tls1 -alpn_client bar,foo -alpn_server bar,foo ^
  -alpn_expected bar & if !errorlevel! neq 0 exit /b 1
%ssltest% -bio_pair -tls1 -alpn_client foo,bar -alpn_server bar,foo ^
  -alpn_expected bar & if !errorlevel! neq 0 exit /b 1
%ssltest% -bio_pair -tls1 -alpn_client baz -alpn_server bar,foo & if !errorlevel! neq 0 exit /b 1

endlocal
