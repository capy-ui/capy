@echo off
setlocal enabledelayedexpansion
REM	servertest.bat

set servertest_bin=%1
set servertest_bin=%servertest_bin:/=\%
if not exist %servertest_bin% exit /b 1

%servertest_bin% %srcdir%\server.pem %srcdir%\server.pem %srcdir%\ca.pem
if !errorlevel! neq 0 (
	exit /b 1
)

endlocal
