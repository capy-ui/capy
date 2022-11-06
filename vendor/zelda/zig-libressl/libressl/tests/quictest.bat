@echo off
setlocal enabledelayedexpansion
REM	quictest.bat

set quictest_bin=%1
set quictest_bin=%quictest_bin:/=\%
if not exist %quictest_bin% exit /b 1

%quictest_bin% %srcdir%\server.pem %srcdir%\server.pem %srcdir%\ca.pem
if !errorlevel! neq 0 (
	exit /b 1
)

endlocal
