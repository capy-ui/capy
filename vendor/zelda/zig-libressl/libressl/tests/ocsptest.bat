@echo off
setlocal enabledelayedexpansion
REM	ocspocsp_test_bin.bat

set ocsp_test_bin=%1
set ocsp_test_bin=%ocsp_test_bin:/=\%
if not exist %ocsp_test_bin% exit /b 1

%ocsp_test_bin% www.amazon.com 443 & if !errorlevel! neq 0 exit /b 1
%ocsp_test_bin% cloudflare.com 443 & if !errorlevel! neq 0 exit /b 1

endlocal
