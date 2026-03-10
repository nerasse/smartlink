@echo off
setlocal

set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"

node "%ROOT%\smartlink.js" setup %*
exit /b %ERRORLEVEL%
