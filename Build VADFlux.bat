@echo off
setlocal EnableDelayedExpansion

set "PYTHON=python"
set "BUILD_DIR=%~dp0_vadflux_build"
set "SCRIPT=%~dp0scripts\vadflux.py"
set "OUT=%~dp0vadflux.exe"

echo Operacion: build vadflux
echo.

if not exist "%SCRIPT%" (
    echo Error: no se encontro "%SCRIPT%".
    goto :fin
)

if exist "%BUILD_DIR%" rmdir /s /q "%BUILD_DIR%" 2>nul
mkdir "%BUILD_DIR%" >nul 2>nul
if errorlevel 1 (
    echo Error: no se pudo crear "%BUILD_DIR%".
    goto :fin
)

"%PYTHON%" -c "import PyInstaller, librosa, numba, numpy, soundfile, torch" >nul 2>nul
if errorlevel 1 (
    echo Faltan dependencias de build.
    echo Ejecuta:
    echo   %PYTHON% -m pip install pyinstaller torch torchaudio librosa soundfile numpy numba
    goto :fin
)

"%PYTHON%" -m PyInstaller --onefile --console --name vadflux --distpath "%~dp0" --workpath "%BUILD_DIR%\work" --specpath "%BUILD_DIR%" "%SCRIPT%"
if errorlevel 1 (
    echo Error: PyInstaller no pudo construir vadflux.exe.
    goto :fin
)

if exist "%OUT%" (
    echo Salida: "%OUT%"
) else (
    echo Error: no se encontro "%OUT%".
)

:fin
if exist "%BUILD_DIR%" rmdir /s /q "%BUILD_DIR%" 2>nul
echo.
echo Finalizado.
pause
exit /b
