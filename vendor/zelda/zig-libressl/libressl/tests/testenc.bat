@echo off
setlocal enabledelayedexpansion
REM	testenc.bat

set test=p

set openssl_bin=%1
set openssl_bin=%openssl_bin:/=\%
if not exist %openssl_bin% exit /b 1

copy %srcdir%\openssl.cnf %test%

echo cat
%openssl_bin% enc -in %test% -out %test%.cipher
%openssl_bin% enc -in %test%.cipher -out %test%.clear
fc /b %test% %test%.clear
if !errorlevel! neq 0 (
	exit /b 1
) else (
	del %test%.cipher %test%.clear
)

echo base64
%openssl_bin% enc -a -e -in %test% -out %test%.cipher
%openssl_bin% enc -a -d -in %test%.cipher -out %test%.clear
fc /b %test% %test%.clear
if !errorlevel! neq 0 (
	exit /b 1
) else (
	del %test%.cipher %test%.clear
)

for %%i in (
	aes-128-cbc aes-128-cfb aes-128-cfb1 aes-128-cfb8
	aes-128-ecb aes-128-ofb aes-192-cbc aes-192-cfb
	aes-192-cfb1 aes-192-cfb8 aes-192-ecb aes-192-ofb
	aes-256-cbc aes-256-cfb aes-256-cfb1 aes-256-cfb8
	aes-256-ecb aes-256-ofb
	bf-cbc bf-cfb bf-ecb bf-ofb
	cast-cbc cast5-cbc cast5-cfb cast5-ecb cast5-ofb
	des-cbc des-cfb des-cfb8 des-ecb des-ede
	des-ede-cbc des-ede-cfb des-ede-ofb des-ede3
	des-ede3-cbc des-ede3-cfb des-ede3-ofb des-ofb desx-cbc
	rc2-40-cbc rc2-64-cbc rc2-cbc rc2-cfb rc2-ecb rc2-ofb
	rc4 rc4-40
) do (
	echo %%i
	%openssl_bin% %%i -e -k test -in %test% -out %test%.%%i.cipher
	%openssl_bin% %%i -d -k test -in %test%.%%i.cipher -out %test%.%%i.clear
	fc /b %test% %test%.%%i.clear
	if !errorlevel! neq 0 (
		exit /b 1
	) else (
		del %test%.%%i.cipher %test%.%%i.clear
	)

	echo %%i base64
	%openssl_bin% %%i -a -e -k test -in %test% -out %test%.%%i.cipher
	%openssl_bin% %%i -a -d -k test -in %test%.%%i.cipher -out %test%.%%i.clear
	fc /b %test% %test%.%%i.clear
	if !errorlevel! neq 0 (
		exit /b 1
	) else (
		del %test%.%%i.cipher %test%.%%i.clear
	)
)

del %test%
endlocal
