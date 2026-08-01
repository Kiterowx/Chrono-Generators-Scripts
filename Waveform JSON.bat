@echo off
setlocal EnableDelayedExpansion

set "PYTHON=python"
set "AUDIO_EXT=wav"

echo Operacion: waveform json
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
call :procesar_media "%AUDIO%" "%CD%\%PAD%.waveform.json"
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
for %%F in ("%~1") do call :procesar_media "%%~fF" "%%~dpnF.waveform.json"
exit /b

:procesar_media
set "INPUT=%~1"
set "OUT=%~2"
for %%F in ("%INPUT%") do set "NAME=%%~nxF"
echo Procesando: "!NAME!"
call :run_waveform "!INPUT!" "!OUT!"
if errorlevel 1 (
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

:es_audio
set "ES_AUDIO="
for %%E in (%AUDIO_EXT%) do if /I "%~x1"==".%%E" set "ES_AUDIO=1"
exit /b

:run_waveform
"%PYTHON%" -c "import pathlib, sys; source=pathlib.Path(sys.argv[1]).read_text(encoding='utf-8'); code=source.split('\n### WAVEFORM_PY_BEGIN\n',1)[1].split('\n### WAVEFORM_PY_END',1)[0]; sys.argv=[sys.argv[1]]+sys.argv[2:]; exec(compile(code, sys.argv[0], 'exec'))" "%~f0" "%~1" "%~2"
exit /b %ERRORLEVEL%

### WAVEFORM_PY_BEGIN
from __future__ import annotations

import argparse
import math
import os
import re
import subprocess
import sys
import tempfile
from array import array
from pathlib import Path

SAMPLE_RATE = 48000
CHANNELS = 1
BITS = 16
BYTES_PER_SAMPLE = 2
BASE_POINT_MS = 1
SAMPLES_PER_POINT = SAMPLE_RATE // 1000
READ_BYTES = 262144
MAX_STREAM_INDEX = 63


def round_int(value: float) -> int:
    return int(math.floor((float(value) if value is not None else 0.0) + 0.5))


def safe_name(value: str, fallback: str = "waveform") -> str:
    out = re.sub(r'[\\/:*?"<>|]+', "_", str(value or "").strip())
    out = re.sub(r"\s+", "_", out)
    out = re.sub(r"_+", "_", out).strip("_. ")
    lower = out.lower()
    reserved = lower in {"con", "prn", "aux", "nul"} or re.fullmatch(r"com[1-9]|lpt[1-9]", lower or "") is not None
    if not out or out in {".", ".."} or re.fullmatch(r"\.+", out) or reserved:
        return fallback
    return out


class Level:
    __slots__ = ("index", "scale", "point_ms", "samples_per_point", "peaks", "pending")

    def __init__(self, index: int) -> None:
        self.index = index
        self.scale = 2 ** index
        self.point_ms = BASE_POINT_MS * self.scale
        self.samples_per_point = SAMPLES_PER_POINT * self.scale
        self.peaks = array("h")
        self.pending: tuple[float, float] | None = None


class Pyramid:
    def __init__(self) -> None:
        self.levels: list[Level] = []

    def ensure(self, index: int) -> Level:
        while len(self.levels) <= index:
            self.levels.append(Level(len(self.levels)))
        return self.levels[index]

    def emit(self, index: int, low: float, high: float) -> None:
        level = self.ensure(index)
        level.peaks.append(round_int(low))
        level.peaks.append(round_int(high))
        if level.pending is None:
            level.pending = (low, high)
        else:
            prev_low, prev_high = level.pending
            level.pending = None
            self.emit(index + 1, min(prev_low, low), max(prev_high, high))

    def flush(self) -> None:
        index = 0
        while index < len(self.levels):
            level = self.levels[index]
            if level.pending is not None and index + 1 < len(self.levels):
                low, high = level.pending
                level.pending = None
                self.emit(index + 1, low, high)
            index += 1


def default_output(input_path: Path) -> Path:
    return input_path.with_name(f"{safe_name(input_path.stem)}.waveform.json")


def decode_audio(input_path: Path, stream: int, ffmpeg: str, temp_dir: Path) -> Path:
    stream = max(0, min(MAX_STREAM_INDEX, int(stream)))
    handle, raw_name = tempfile.mkstemp(prefix="wave2json_", suffix=".s16le", dir=str(temp_dir))
    os.close(handle)
    raw_path = Path(raw_name)
    cmd = [
        ffmpeg,
        "-hide_banner",
        "-nostdin",
        "-loglevel",
        "error",
        "-y",
        "-i",
        str(input_path),
        "-map",
        f"0:a:{stream}",
        "-vn",
        "-ac",
        str(CHANNELS),
        "-ar",
        str(SAMPLE_RATE),
        "-f",
        "s16le",
        str(raw_path),
    ]
    proc = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
    if proc.returncode != 0:
        raw_path.unlink(missing_ok=True)
        detail = (proc.stderr or "").strip()
        raise RuntimeError(detail if detail else "ffmpeg failed")
    if raw_path.stat().st_size <= 0:
        raw_path.unlink(missing_ok=True)
        raise RuntimeError("empty audio")
    return raw_path


def process_pcm(path: Path) -> tuple[Pyramid, int, int]:
    pyramid = Pyramid()
    current_min = 32767
    current_max = -32768
    samples_in_point = 0
    total_samples = 0
    leftover = b""
    with path.open("rb") as src:
        while True:
            data = src.read(READ_BYTES)
            if not data:
                break
            if leftover:
                data = leftover + data
                leftover = b""
            if len(data) % BYTES_PER_SAMPLE:
                leftover = data[-1:]
                data = data[:-1]
            if not data:
                continue
            samples = array("h")
            samples.frombytes(data)
            if sys.byteorder != "little":
                samples.byteswap()
            for sample in samples:
                if sample < current_min:
                    current_min = sample
                if sample > current_max:
                    current_max = sample
                samples_in_point += 1
                total_samples += 1
                if samples_in_point >= SAMPLES_PER_POINT:
                    pyramid.emit(0, current_min, current_max)
                    current_min = 32767
                    current_max = -32768
                    samples_in_point = 0
    if samples_in_point > 0:
        pyramid.emit(0, current_min, current_max)
    pyramid.flush()
    duration_ms = round_int(total_samples * 1000 / SAMPLE_RATE)
    return pyramid, duration_ms, total_samples


def write_peaks(out, peaks: array) -> None:
    chunk: list[str] = []
    first = True
    for value in peaks:
        if first:
            chunk.append(str(int(value)))
            first = False
        else:
            chunk.append("," + str(int(value)))
        if len(chunk) >= 8192:
            out.write("".join(chunk))
            chunk.clear()
    if chunk:
        out.write("".join(chunk))


def write_json(output_path: Path, pyramid: Pyramid, duration_ms: int, total_samples: int) -> None:
    with output_path.open("w", encoding="utf-8", newline="\n") as out:
        out.write("{\n")
        out.write('  "type": "waveform",\n')
        out.write('  "version": 1,\n')
        out.write(f'  "sampleRate": {SAMPLE_RATE},\n')
        out.write(f'  "channels": {CHANNELS},\n')
        out.write(f'  "bits": {BITS},\n')
        out.write('  "amplitudeFormat": "s16",\n')
        out.write('  "amplitudeMin": -32768,\n')
        out.write('  "amplitudeMax": 32767,\n')
        out.write('  "pointLayout": "interleavedMinMax",\n')
        out.write(f'  "durationMs": {duration_ms},\n')
        out.write(f'  "totalSamples": {total_samples},\n')
        out.write('  "levels": [\n')
        for index, level in enumerate(pyramid.levels):
            if index > 0:
                out.write(",\n")
            points = len(level.peaks) // 2
            out.write("    {\n")
            out.write(f'      "scale": {level.scale},\n')
            out.write(f'      "pointMs": {level.point_ms},\n')
            out.write(f'      "samplesPerPoint": {level.samples_per_point},\n')
            out.write(f'      "points": {points},\n')
            out.write('      "peaks": [')
            write_peaks(out, level.peaks)
            out.write("]\n")
            out.write("    }")
        out.write("\n  ]\n")
        out.write("}\n")


def export_waveform(input_path: Path, output_path: Path, stream: int, ffmpeg: str) -> None:
    if not input_path.exists():
        raise RuntimeError("input not found")
    output_path.parent.mkdir(parents=True, exist_ok=True)
    raw_path = decode_audio(input_path, stream, ffmpeg, output_path.parent)
    try:
        pyramid, duration_ms, total_samples = process_pcm(raw_path)
        write_json(output_path, pyramid, duration_ms, total_samples)
    finally:
        raw_path.unlink(missing_ok=True)


def main() -> int:
    parser = argparse.ArgumentParser(description="waveform json")
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path, nargs="?")
    parser.add_argument("--stream", type=int, default=int(os.environ.get("AUDIO_STREAM", "0") or 0))
    parser.add_argument("--ffmpeg", default=os.environ.get("FFMPEG", "ffmpeg"))
    args = parser.parse_args()
    output = args.output if args.output else default_output(args.input)
    try:
        export_waveform(args.input, output, args.stream, args.ffmpeg)
    except Exception as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
### WAVEFORM_PY_END
