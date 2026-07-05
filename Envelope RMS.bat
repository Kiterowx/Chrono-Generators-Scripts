@echo off
setlocal EnableDelayedExpansion

set "FFPROBE=ffprobe"

echo Operacion: envelope
echo.

if not "%~1"=="" (
    for %%A in (%*) do call :procesar_archivo "%%~fA"
    goto :fin
)

set /p INICIO="Inicio: "
set /p FIN="Fin: "
if not defined INICIO goto :fin
if not defined FIN goto :fin

echo.
for /l %%N in (%INICIO%,1,%FIN%) do call :procesar_numero %%N

:fin
echo.
echo Finalizado.
pause
exit /b

:procesar_numero
set "N=%~1"
set "PAD=0%N%"
set "PAD=%PAD:~-2%"
call :buscar_vocals "%CD%\" "" "%N%" "%PAD%"
if not defined VOCALS (
    echo [%PAD%] Omitido: audio no encontrado.
    exit /b
)
call :generar "!VOCALS!" "%CD%\%PAD%_envelope.tsv"
exit /b

:procesar_archivo
if not exist "%~1" (
    echo Omitido: "%~1"
    exit /b
)
for %%F in ("%~1") do call :generar "%%~fF" "%%~dpnF_envelope.tsv"
exit /b

:buscar_vocals
set "VOCALS="
set "DIR=%~1"
set "STEM=%~2"
set "N=%~3"
set "PAD=%~4"
if defined STEM (
    if exist "%DIR%%STEM%_vocals.wav" set "VOCALS=%DIR%%STEM%_vocals.wav"
    if not defined VOCALS if exist "%DIR%%STEM%_Vocals.wav" set "VOCALS=%DIR%%STEM%_Vocals.wav"
    if not defined VOCALS if exist "%DIR%vocals_%STEM%.wav" set "VOCALS=%DIR%vocals_%STEM%.wav"
    if not defined VOCALS if exist "%DIR%%STEM%.wav" set "VOCALS=%DIR%%STEM%.wav"
)
if defined N (
    if not defined VOCALS if exist "%DIR%%N%_vocals.wav" set "VOCALS=%DIR%%N%_vocals.wav"
    if not defined VOCALS if exist "%DIR%%PAD%_vocals.wav" set "VOCALS=%DIR%%PAD%_vocals.wav"
    if not defined VOCALS if exist "%DIR%%N%_Vocals.wav" set "VOCALS=%DIR%%N%_Vocals.wav"
    if not defined VOCALS if exist "%DIR%%PAD%_Vocals.wav" set "VOCALS=%DIR%%PAD%_Vocals.wav"
    if not defined VOCALS if exist "%DIR%vocals_%N%.wav" set "VOCALS=%DIR%vocals_%N%.wav"
    if not defined VOCALS if exist "%DIR%vocals_%PAD%.wav" set "VOCALS=%DIR%vocals_%PAD%.wav"
    if not defined VOCALS if exist "%DIR%%N%.wav" set "VOCALS=%DIR%%N%.wav"
    if not defined VOCALS if exist "%DIR%%PAD%.wav" set "VOCALS=%DIR%%PAD%.wav"
)
if not defined VOCALS if defined PAD (
    pushd "%DIR%" >nul 2>nul
    for /f "delims=" %%V in ('dir /b /a-d "*%PAD%*vocals*.wav" 2^>nul') do if not defined VOCALS set "VOCALS=%DIR%%%V"
    for /f "delims=" %%V in ('dir /b /a-d "*%PAD%*Vocals*.wav" 2^>nul') do if not defined VOCALS set "VOCALS=%DIR%%%V"
    popd >nul 2>nul
)
if not defined VOCALS if defined N (
    pushd "%DIR%" >nul 2>nul
    for /f "delims=" %%V in ('dir /b /a-d "*%N%*vocals*.wav" 2^>nul') do if not defined VOCALS set "VOCALS=%DIR%%%V"
    popd >nul 2>nul
)
exit /b

:generar
set "INPUT=%~1"
set "OUT=%~2"
for %%F in ("%INPUT%") do (
    set "DIR=%%~dpF"
    set "NAME=%%~nxF"
)
echo Procesando: "!NAME!"
pushd "!DIR!" >nul 2>nul
"%FFPROBE%" -f lavfi -i "amovie='!NAME!',astats=metadata=1:reset=1" -show_entries frame=pts_time:frame_tags=lavfi.astats.Overall.RMS_level -of csv=p=0 -v error 1> "!OUT!"
set "STATUS=%ERRORLEVEL%"
popd >nul 2>nul
if not "%STATUS%"=="0" (
    echo Error: "!NAME!"
    exit /b
)
if not exist "!OUT!" (
    echo Error: "!OUT!"
    exit /b
)
for %%S in ("!OUT!") do set "SIZE=%%~zS"
if "!SIZE!"=="0" (
    echo Error: "!OUT!"
    exit /b
)
echo Salida: "!OUT!"
exit /b
