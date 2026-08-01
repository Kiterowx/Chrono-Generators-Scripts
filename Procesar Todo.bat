@echo off
setlocal EnableDelayedExpansion

set "FFMPEG=ffmpeg"
set "FFPROBE=ffprobe"
set "VADFLUX=vadflux.exe"
set "SCXVID=SCXvid.exe"
set "PYTHON=python"
set "VIDEO_EXT=mkv mp4 avi mov ts m4v webm"
set "AUDIO_EXT=wav"

echo Operacion: completo
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
call :buscar_video "%CD%\" "" "%N%" "%PAD%"
call :buscar_audio "%CD%\" "" "%N%" "%PAD%"
if not defined VIDEO (
    echo [%PAD%] Omitido: video para keyframes no encontrado.
    exit /b
)
if not defined AUDIO (
    echo [%PAD%] Omitido: WAV vocal no encontrado.
    exit /b
)
call :procesar_par "!VIDEO!" "!AUDIO!" "%CD%\" "%PAD%"
exit /b

:procesar_archivo
if not exist "%~1" (
    echo Omitido: "%~1"
    exit /b
)
for %%F in ("%~1") do (
    set "INPUT=%%~fF"
    set "DIR=%%~dpF"
    set "STEM=%%~nF"
)
call :es_video "!INPUT!"
if defined ES_VIDEO (
    set "VIDEO=!INPUT!"
    call :buscar_audio "!DIR!" "!STEM!" "" ""
    if not defined AUDIO (
        echo Omitido: WAV vocal emparejado no encontrado para "!INPUT!".
        exit /b
    )
    call :procesar_par "!VIDEO!" "!AUDIO!" "!DIR!" "!STEM!"
    exit /b
)
call :es_audio "!INPUT!"
if not defined ES_AUDIO (
    echo Omitido: se requiere un video y su WAV vocal: "!INPUT!"
    exit /b
)
set "AUDIO=!INPUT!"
call :buscar_video "!DIR!" "!STEM!" "" ""
if not defined VIDEO (
    echo Omitido: video emparejado para keyframes no encontrado para "!INPUT!".
    exit /b
)
call :procesar_par "!VIDEO!" "!AUDIO!" "!DIR!" "!STEM!"
exit /b

:procesar_par
set "VIDEO=%~1"
set "AUDIO=%~2"
set "DIR=%~3"
set "STEM=%~4"
set "BASE=%DIR%%STEM%_Retimes"
set "ENVELOPE=%DIR%%STEM%_envelope.tsv"
set "WAVEFORM=%DIR%%STEM%.waveform.json"
for %%F in ("%VIDEO%") do set "VIDEO_NAME=%%~nxF"
for %%F in ("%AUDIO%") do set "AUDIO_NAME=%%~nxF"
echo Video para keyframes: "!VIDEO_NAME!"
echo Audio vocal para señales: "!AUDIO_NAME!"
call :keyframes "!VIDEO!"
call :retimes "!AUDIO!" "!BASE!"
call :waveform "!AUDIO!" "!WAVEFORM!"
call :envelope "!AUDIO!" "!ENVELOPE!"
exit /b

:buscar_video
set "VIDEO="
set "DIR=%~1"
set "STEM=%~2"
set "N=%~3"
set "PAD=%~4"
if defined STEM (
    for %%E in (%VIDEO_EXT%) do if not defined VIDEO if exist "%DIR%%STEM%.%%E" set "VIDEO=%DIR%%STEM%.%%E"
)
if defined N (
    for %%E in (%VIDEO_EXT%) do (
        if not defined VIDEO if exist "%DIR%%N%.%%E" set "VIDEO=%DIR%%N%.%%E"
        if not defined VIDEO if exist "%DIR%%PAD%.%%E" set "VIDEO=%DIR%%PAD%.%%E"
    )
)
exit /b

:buscar_audio
set "AUDIO="
set "DIR=%~1"
set "STEM=%~2"
set "N=%~3"
set "PAD=%~4"
if defined STEM (
    if exist "%DIR%%STEM%.wav" set "AUDIO=%DIR%%STEM%.wav"
    if not defined AUDIO if exist "%DIR%%STEM%_vocals.wav" set "AUDIO=%DIR%%STEM%_vocals.wav"
    if not defined AUDIO if exist "%DIR%%STEM%_Vocals.wav" set "AUDIO=%DIR%%STEM%_Vocals.wav"
    if not defined AUDIO if exist "%DIR%vocals_%STEM%.wav" set "AUDIO=%DIR%vocals_%STEM%.wav"
)
if defined N (
    if not defined AUDIO if exist "%DIR%%N%.wav" set "AUDIO=%DIR%%N%.wav"
    if not defined AUDIO if exist "%DIR%%PAD%.wav" set "AUDIO=%DIR%%PAD%.wav"
    if not defined AUDIO if exist "%DIR%%N%_vocals.wav" set "AUDIO=%DIR%%N%_vocals.wav"
    if not defined AUDIO if exist "%DIR%%PAD%_vocals.wav" set "AUDIO=%DIR%%PAD%_vocals.wav"
    if not defined AUDIO if exist "%DIR%%N%_Vocals.wav" set "AUDIO=%DIR%%N%_Vocals.wav"
    if not defined AUDIO if exist "%DIR%%PAD%_Vocals.wav" set "AUDIO=%DIR%%PAD%_Vocals.wav"
    if not defined AUDIO if exist "%DIR%vocals_%N%.wav" set "AUDIO=%DIR%vocals_%N%.wav"
    if not defined AUDIO if exist "%DIR%vocals_%PAD%.wav" set "AUDIO=%DIR%vocals_%PAD%.wav"
)
exit /b

:keyframes
set "INPUT=%~1"
for %%F in ("%INPUT%") do set "OUT=%%~dpnF_keyframes.log"
"%FFMPEG%" -hide_banner -nostdin -loglevel error -i "%INPUT%" -f yuv4mpegpipe -vf scale=640:360 -pix_fmt yuv420p -vsync drop - | "%SCXVID%" "!OUT!"
if errorlevel 1 (
    echo Error: keyframes.
    exit /b
)
echo Salida: "!OUT!"
exit /b

:retimes
set "INPUT=%~1"
set "BASE=%~2"
set "PRE=%BASE%_%RANDOM%_pre.wav"
set "LOG30=%BASE%_30.txt"
set "LOG40=%BASE%_40.txt"
set "LOG50=%BASE%_50.txt"
set "VAD=%BASE%_vad.tsv"
set "FLUX=%BASE%_flux.tsv"
set "SPECTRAL=%BASE%_spectrum.tsv"
set "VADLOG=%BASE%_vadflux.log"
"%FFMPEG%" -hide_banner -nostdin -loglevel error -y -i "%INPUT%" -ac 1 -ar 16000 -af "highpass=f=80, lowpass=f=8000, dynaudnorm=f=150:g=5" "!PRE!"
if errorlevel 1 (
    echo Error: audio.
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
call :run_spectral "!PRE!" "!SPECTRAL!"
set "SPECTRAL_STATUS=%ERRORLEVEL%"
del "!PRE!" 2>nul
echo Salida: "!LOG30!"
echo Salida: "!LOG40!"
echo Salida: "!LOG50!"
if exist "!VAD!" echo Salida: "!VAD!"
if exist "!FLUX!" echo Salida: "!FLUX!"
if not "%SPECTRAL_STATUS%"=="0" (
    echo Error: spectral.
    exit /b
)
if not exist "!SPECTRAL!" (
    echo Error: spectral.
    exit /b
)
for %%S in ("!SPECTRAL!") do set "SIZE=%%~zS"
if "!SIZE!"=="0" (
    echo Error: spectral.
    exit /b
)
echo Salida: "!SPECTRAL!"
exit /b

:waveform
set "INPUT=%~1"
set "OUT=%~2"
call :run_waveform "%INPUT%" "%OUT%"
if errorlevel 1 (
    echo Error: waveform json.
    exit /b
)
if not exist "%OUT%" (
    echo Error: waveform json.
    exit /b
)
for %%S in ("%OUT%") do set "SIZE=%%~zS"
if "!SIZE!"=="0" (
    echo Error: waveform json.
    exit /b
)
echo Salida: "%OUT%"
exit /b

:envelope
set "INPUT=%~1"
set "OUT=%~2"
for %%F in ("%INPUT%") do (
    set "INPUT_DIR=%%~dpF"
    set "INPUT_NAME=%%~nxF"
)
pushd "!INPUT_DIR!" >nul 2>nul
"%FFPROBE%" -f lavfi -i "amovie='!INPUT_NAME!',astats=metadata=1:reset=1" -show_entries frame=pts_time:frame_tags=lavfi.astats.Overall.RMS_level -of csv=p=0 -v error 1> "!OUT!"
set "STATUS=%ERRORLEVEL%"
popd >nul 2>nul
if not "%STATUS%"=="0" (
    echo Error: envelope.
    exit /b
)
if not exist "!OUT!" (
    echo Error: envelope.
    exit /b
)
for %%S in ("!OUT!") do set "SIZE=%%~zS"
if "!SIZE!"=="0" (
    echo Error: envelope.
    exit /b
)
echo Salida: "!OUT!"
exit /b

:es_video
set "ES_VIDEO="
for %%E in (%VIDEO_EXT%) do if /I "%~x1"==".%%E" set "ES_VIDEO=1"
exit /b

:es_audio
set "ES_AUDIO="
for %%E in (%AUDIO_EXT%) do if /I "%~x1"==".%%E" set "ES_AUDIO=1"
exit /b

:run_spectral
"%PYTHON%" -c "import pathlib, sys; source=pathlib.Path(sys.argv[1]).read_text(encoding='utf-8'); code=source.split('\n### SPECTRAL_PY_BEGIN\n',1)[1].split('\n### SPECTRAL_PY_END',1)[0]; sys.argv=[sys.argv[1]]+sys.argv[2:]; exec(compile(code, sys.argv[0], 'exec'))" "%~f0" "%~1" "%~2"
exit /b %ERRORLEVEL%

:run_waveform
"%PYTHON%" -c "import pathlib, sys; source=pathlib.Path(sys.argv[1]).read_text(encoding='utf-8'); code=source.split('\n### WAVEFORM_PY_BEGIN\n',1)[1].split('\n### WAVEFORM_PY_END',1)[0]; sys.argv=[sys.argv[1]]+sys.argv[2:]; exec(compile(code, sys.argv[0], 'exec'))" "%~f0" "%~1" "%~2"
exit /b %ERRORLEVEL%

### SPECTRAL_PY_BEGIN
from __future__ import annotations

import argparse
import csv
import math
import wave
from pathlib import Path
from typing import Tuple

import numpy as np


def read_wav(path: Path) -> Tuple[int, np.ndarray]:
    with wave.open(str(path), "rb") as wf:
        sr = wf.getframerate()
        channels = wf.getnchannels()
        sampwidth = wf.getsampwidth()
        nframes = wf.getnframes()
        raw = wf.readframes(nframes)

    if sampwidth == 1:
        data = np.frombuffer(raw, dtype=np.uint8).astype(np.float32)
        data = (data - 128.0) / 128.0
    elif sampwidth == 2:
        data = np.frombuffer(raw, dtype="<i2").astype(np.float32) / 32768.0
    elif sampwidth == 3:
        b = np.frombuffer(raw, dtype=np.uint8).reshape(-1, 3)
        signed = (b[:, 0].astype(np.int32)
                  | (b[:, 1].astype(np.int32) << 8)
                  | (b[:, 2].astype(np.int32) << 16))
        signed = np.where(signed & 0x800000, signed - 0x1000000, signed)
        data = signed.astype(np.float32) / 8388608.0
    elif sampwidth == 4:
        data = np.frombuffer(raw, dtype="<i4").astype(np.float32) / 2147483648.0
    else:
        raise ValueError(f"Unsupported WAV sample width: {sampwidth} bytes")

    if channels > 1:
        data = data.reshape(-1, channels).mean(axis=1)
    return sr, data


def db(x: np.ndarray | float, floor: float = 1e-12) -> np.ndarray | float:
    return 20.0 * np.log10(np.maximum(np.asarray(x), floor))


def band_energy(power: np.ndarray, freqs: np.ndarray, lo: float, hi: float) -> float:
    m = (freqs >= lo) & (freqs < hi)
    if not np.any(m):
        return 0.0
    return float(np.sum(power[m]))


def robust_norm(x: np.ndarray, lo_q: float = 10, hi_q: float = 90) -> np.ndarray:
    if x.size == 0:
        return x
    lo = np.percentile(x, lo_q)
    hi = np.percentile(x, hi_q)
    return np.clip((x - lo) / max(hi - lo, 1e-6), 0.0, 1.0)


def sigmoid(x: np.ndarray) -> np.ndarray:
    return 1.0 / (1.0 + np.exp(-np.clip(x, -50, 50)))


def compute_features(audio: np.ndarray, sr: int, win_ms: float, hop_ms: float) -> list[dict[str, float]]:
    win = max(64, int(round(sr * win_ms / 1000.0)))
    hop = max(16, int(round(sr * hop_ms / 1000.0)))
    if len(audio) < win:
        audio = np.pad(audio, (0, win - len(audio)))
    window = np.hanning(win).astype(np.float32)
    freqs = np.fft.rfftfreq(win, 1.0 / sr)

    rows = []
    prev_mag = None
    for start in range(0, len(audio) - win + 1, hop):
        frame = audio[start:start + win]
        wframe = frame * window
        rms = math.sqrt(float(np.mean(frame * frame)) + 1e-12)
        peak = float(np.max(np.abs(frame))) if frame.size else 0.0
        zcr = float(np.mean(np.abs(np.diff(np.signbit(frame)).astype(np.float32)))) if frame.size > 1 else 0.0
        mag = np.abs(np.fft.rfft(wframe)) + 1e-12
        power = mag * mag
        psum = float(np.sum(power)) + 1e-12
        centroid = float(np.sum(freqs * power) / psum)
        flatness = float(np.exp(np.mean(np.log(mag))) / (np.mean(mag) + 1e-12))
        if prev_mag is None:
            flux = 0.0
        else:
            diff = np.maximum(0.0, mag / (np.linalg.norm(mag) + 1e-12) - prev_mag)
            flux = float(np.linalg.norm(diff))
        prev_mag = mag / (np.linalg.norm(mag) + 1e-12)
        b1 = band_energy(power, freqs, 80, 300)
        b2 = band_energy(power, freqs, 300, 1000)
        b3 = band_energy(power, freqs, 1000, 3000)
        b4 = band_energy(power, freqs, 3000, min(6000, sr / 2))
        rows.append({
            "time_ms": (start + win / 2) * 1000.0 / sr,
            "rms_db": float(db(rms)),
            "peak_db": float(db(peak)),
            "zcr": zcr,
            "centroid_hz": centroid,
            "flatness": flatness,
            "flux": flux,
            "band_80_300": b1,
            "band_300_1000": b2,
            "band_1000_3000": b3,
            "band_3000_6000": b4,
        })

    if not rows:
        return rows

    rms_arr = np.array([r["rms_db"] for r in rows], dtype=np.float64)
    flux_arr = np.array([r["flux"] for r in rows], dtype=np.float64)
    flat_arr = np.array([r["flatness"] for r in rows], dtype=np.float64)
    cent_arr = np.array([r["centroid_hz"] for r in rows], dtype=np.float64)
    zcr_arr = np.array([r["zcr"] for r in rows], dtype=np.float64)
    b2_arr = np.array([r["band_300_1000"] for r in rows], dtype=np.float64)
    b3_arr = np.array([r["band_1000_3000"] for r in rows], dtype=np.float64)
    ball_arr = np.array([r["band_80_300"] + r["band_300_1000"] + r["band_1000_3000"] + r["band_3000_6000"] for r in rows], dtype=np.float64) + 1e-12

    rms_n = robust_norm(rms_arr, 8, 92)
    flux_n = np.clip(flux_arr / max(np.percentile(flux_arr, 95), 1e-6), 0.0, 1.0)
    speech_band = np.clip((b2_arr + b3_arr) / ball_arr, 0.0, 1.0)
    centroid_ok = ((cent_arr >= 150) & (cent_arr <= 4300)).astype(np.float64)
    zcr_ok = np.exp(-np.maximum(0.0, zcr_arr - 0.20) * 8.0)
    flat_penalty = np.clip(flat_arr, 0.0, 1.0)

    score = (-3.15
             + 4.85 * rms_n
             + 1.55 * speech_band
             + 0.58 * flux_n
             + 0.48 * centroid_ok
             + 0.35 * zcr_ok
             - 1.10 * flat_penalty)
    p = sigmoid(score)

    if len(p) >= 3:
        p = np.convolve(p, np.array([0.20, 0.60, 0.20]), mode="same")
    for r, pv in zip(rows, p):
        r["speech_p"] = float(np.clip(pv, 0.0, 1.0))
    return rows


def write_tsv(path: Path, rows: list[dict[str, float]]) -> None:
    fields = ["time_ms", "rms_db", "peak_db", "zcr", "centroid_hz", "flatness", "flux",
              "band_80_300", "band_300_1000", "band_1000_3000", "band_3000_6000", "speech_p"]
    with path.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fields, delimiter="\t", lineterminator="\n")
        w.writeheader()
        for r in rows:
            w.writerow({k: f"{r.get(k, 0.0):.6f}" for k in fields})


def main() -> int:
    ap = argparse.ArgumentParser(description="spectral features")
    ap.add_argument("input_wav", type=Path)
    ap.add_argument("output_tsv", type=Path)
    ap.add_argument("--win-ms", type=float, default=32.0)
    ap.add_argument("--hop-ms", type=float, default=10.0)
    args = ap.parse_args()

    sr, audio = read_wav(args.input_wav)
    rows = compute_features(audio, sr, args.win_ms, args.hop_ms)
    write_tsv(args.output_tsv, rows)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
### SPECTRAL_PY_END

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
