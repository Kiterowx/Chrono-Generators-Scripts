@echo off
setlocal EnableDelayedExpansion

set "FFMPEG=ffmpeg"
set "SCXVID=SCXvid.exe"
set "VIDEO_EXT=mkv mp4 avi mov ts m4v webm"

echo Operacion: keyframes
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
set "VIDEO="
for %%E in (%VIDEO_EXT%) do (
    if not defined VIDEO if exist "%N%.%%E" set "VIDEO=%N%.%%E"
    if not defined VIDEO if exist "%PAD%.%%E" set "VIDEO=%PAD%.%%E"
)
if not defined VIDEO (
    echo [%PAD%] Omitido: archivo no encontrado.
    exit /b
)
call :procesar_archivo "%VIDEO%"
exit /b

:procesar_archivo
if not exist "%~1" (
    echo Omitido: "%~1"
    exit /b
)
call :es_video "%~1"
if not defined ES_VIDEO (
    echo Omitido: "%~1"
    exit /b
)
for %%F in ("%~1") do (
    set "INPUT=%%~fF"
    set "OUT=%%~dpnF_keyframes.log"
    set "NAME=%%~nxF"
)
echo Procesando: "!NAME!"
"%FFMPEG%" -hide_banner -nostdin -loglevel error -i "!INPUT!" -f yuv4mpegpipe -vf scale=640:360 -pix_fmt yuv420p -vsync drop - | "%SCXVID%" "!OUT!"
if errorlevel 1 (
    echo Error: "!NAME!"
    exit /b
)
echo Salida: "!OUT!"
exit /b

:es_video
set "ES_VIDEO="
for %%E in (%VIDEO_EXT%) do if /I "%~x1"==".%%E" set "ES_VIDEO=1"
exit /b
