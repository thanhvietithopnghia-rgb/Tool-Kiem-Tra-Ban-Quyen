@echo off
setlocal EnableExtensions
cd /d "%~dp0"

if exist "%~dp0Tool-Kiem-Tra-v4.4.exe" goto RUN_ROOT
if exist "%~dp0dist\Tool-Kiem-Tra-v4.4.exe" goto RUN_DIST
goto SOURCE_MODE

:SOURCE_MODE
if not exist "%~dp0Giao-Dien.ps1" goto MISSING
set "TOOL_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "TOOL_PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
echo Dang chay che do ma nguon chi doc bang PowerShell native.
echo Chuc nang quan tri va enterprise se bi khoa cho den khi build va chay ban EXE an toan.
"%TOOL_PS%" -NoProfile -ExecutionPolicy RemoteSigned -STA -File "%~dp0Giao-Dien.ps1"
exit /b %ERRORLEVEL%

:RUN_ROOT
start "" /wait "%~dp0Tool-Kiem-Tra-v4.4.exe"
exit /b %ERRORLEVEL%

:RUN_DIST
start "" /wait "%~dp0dist\Tool-Kiem-Tra-v4.4.exe"
exit /b %ERRORLEVEL%

:MISSING
echo Khong tim thay Giao-Dien.ps1.
echo Hay giu nguyen cac tep trong cung mot thu muc.
pause
exit /b 1
