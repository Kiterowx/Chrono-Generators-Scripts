@echo off
setlocal DisableDelayedExpansion
set "PYTHON=python"
if exist "%~dp0.venv\Scripts\python.exe" set "PYTHON=%~dp0.venv\Scripts\python.exe"
"%PYTHON%" "%~dp0scripts\generate.py" waveform %*
set "STATUS=%ERRORLEVEL%"
if not "%STATUS%"=="0" echo Error: check the message above.
echo Press any key to close...
pause >nul
exit /b %STATUS%
