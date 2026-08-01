@echo off
setlocal EnableDelayedExpansion

set "FFMPEG=ffmpeg"
set "VADFLUX=vadflux.exe"
set "AUDIO_EXT=wav"

echo Operacion: retimes
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
set "AUDIO="
for %%E in (%AUDIO_EXT%) do (
    if not defined AUDIO if exist "%N%.%%E" set "AUDIO=%N%.%%E"
    if not defined AUDIO if exist "%PAD%.%%E" set "AUDIO=%PAD%.%%E"
)
if not defined AUDIO (
    echo [%PAD%] Omitido: WAV vocal no encontrado.
    exit /b
)
call :procesar_media "%AUDIO%" "%PAD%_Retimes"
exit /b

:procesar_archivo
if not exist "%~1" (
    echo Omitido: "%~1"
    exit /b
)
call :es_audio "%~1"
if not defined ES_AUDIO (
    echo Omitido: se requiere un WAV vocal: "%~1"
    exit /b
)
for %%F in ("%~1") do call :procesar_media "%%~fF" "%%~nF_Retimes"
exit /b

:procesar_media
set "INPUT=%~1"
set "BASE=%~dp1%~2"
set "PRE=%BASE%_%RANDOM%_pre.wav"
set "LOG30=%BASE%_30.txt"
set "LOG40=%BASE%_40.txt"
set "LOG50=%BASE%_50.txt"
set "VAD=%BASE%_vad.tsv"
set "FLUX=%BASE%_flux.tsv"
set "VADLOG=%BASE%_vadflux.log"
for %%F in ("%INPUT%") do set "NAME=%%~nxF"
echo Procesando: "!NAME!"
"%FFMPEG%" -hide_banner -nostdin -loglevel error -y -i "!INPUT!" -ac 1 -ar 16000 -af "highpass=f=80, lowpass=f=8000, dynaudnorm=f=150:g=5" "!PRE!"
if errorlevel 1 (
    echo Error: "!NAME!"
    exit /b
)
"%FFMPEG%" -hide_banner -nostdin -i "!PRE!" -af "silencedetect=n=-30dB:d=0.03" -f null - 2> "!LOG30!"
"%FFMPEG%" -hide_banner -nostdin -i "!PRE!" -af "silencedetect=n=-40dB:d=0.03" -f null - 2> "!LOG40!"
"%FFMPEG%" -hide_banner -nostdin -i "!PRE!" -af "silencedetect=n=-50dB:d=0.03" -f null - 2> "!LOG50!"
"%VADFLUX%" "!PRE!" --vad "!VAD!" --flux "!FLUX!" > "!VADLOG!" 2>&1
if errorlevel 1 (
    echo Error: "!VADLOG!"
) else (
    del "!VADLOG!" 2>nul
)
del "!PRE!" 2>nul
echo Salida: "!LOG30!"
echo Salida: "!LOG40!"
echo Salida: "!LOG50!"
if exist "!VAD!" echo Salida: "!VAD!"
if exist "!FLUX!" echo Salida: "!FLUX!"
exit /b

:es_audio
set "ES_AUDIO="
for %%E in (%AUDIO_EXT%) do if /I "%~x1"==".%%E" set "ES_AUDIO=1"
exit /b
