@echo off
setlocal EnableDelayedExpansion

set "FFMPEG=ffmpeg"
set "PYTHON=python"
set "MEDIA_EXT=mkv mp4 avi mov ts m4v webm aac wav flac mp3 m4a opus ogg"

echo Operacion: spectral
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
set "MEDIA="
for %%E in (%MEDIA_EXT%) do (
    if not defined MEDIA if exist "%N%.%%E" set "MEDIA=%N%.%%E"
    if not defined MEDIA if exist "%PAD%.%%E" set "MEDIA=%PAD%.%%E"
)
if not defined MEDIA (
    echo [%PAD%] Omitido: archivo no encontrado.
    exit /b
)
call :procesar_media "%MEDIA%" "%PAD%_Retimes"
exit /b

:procesar_archivo
if not exist "%~1" (
    echo Omitido: "%~1"
    exit /b
)
for %%F in ("%~1") do call :procesar_media "%%~fF" "%%~nF_Retimes"
exit /b

:procesar_media
set "INPUT=%~1"
set "BASE=%~dp1%~2"
set "PRE=%BASE%_%RANDOM%_spectral_pre.wav"
set "OUT=%BASE%_spectrum.tsv"
for %%F in ("%INPUT%") do set "NAME=%%~nxF"
echo Procesando: "!NAME!"
"%FFMPEG%" -hide_banner -nostdin -loglevel error -y -i "!INPUT!" -ac 1 -ar 16000 -af "highpass=f=80, lowpass=f=8000, dynaudnorm=f=150:g=5" "!PRE!"
if errorlevel 1 (
    echo Error: "!NAME!"
    exit /b
)
call :run_spectral "!PRE!" "!OUT!"
set "STATUS=%ERRORLEVEL%"
del "!PRE!" 2>nul
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

:run_spectral
"%PYTHON%" -c "import pathlib, sys; source=pathlib.Path(sys.argv[1]).read_text(encoding='utf-8'); code=source.split('\n### SPECTRAL_PY_BEGIN\n',1)[1].split('\n### SPECTRAL_PY_END',1)[0]; sys.argv=[sys.argv[1]]+sys.argv[2:]; exec(compile(code, sys.argv[0], 'exec'))" "%~f0" "%~1" "%~2"
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
