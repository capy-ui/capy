@echo off
setlocal enabledelayedexpansion
REM	pq_test.bat

set pq_test_bin=%1
set pq_test_bin=%pq_test_bin:/=\%
if not exist %pq_test_bin% exit /b 1

set pq_output=pq_output.txt
if exist %pq_output% del %pq_output%

%pq_test_bin% > %pq_output%
fc /b %pq_output% %srcdir%\pq_expected.txt

endlocal
