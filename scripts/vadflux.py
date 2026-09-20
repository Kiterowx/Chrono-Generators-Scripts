import argparse
import os
import tempfile

os.environ.setdefault(
    "NUMBA_CACHE_DIR",
    os.path.join(tempfile.gettempdir(), "chrono_vadflux_numba_cache"),
)

import numpy as np
import numba
import soundfile as sf
import torch


_numba_jit = numba.jit
_numba_njit = numba.njit
_numba_vectorize = numba.vectorize
_numba_guvectorize = numba.guvectorize


def _without_numba_cache(kwargs: dict) -> dict:
    if "cache" not in kwargs:
        return kwargs
    out = dict(kwargs)
    out["cache"] = False
    return out


def _jit_no_cache(*args, **kwargs):
    return _numba_jit(*args, **_without_numba_cache(kwargs))


def _njit_no_cache(*args, **kwargs):
    return _numba_njit(*args, **_without_numba_cache(kwargs))


def _vectorize_no_cache(*args, **kwargs):
    return _numba_vectorize(*args, **_without_numba_cache(kwargs))


def _guvectorize_no_cache(*args, **kwargs):
    return _numba_guvectorize(*args, **_without_numba_cache(kwargs))


numba.jit = _jit_no_cache
numba.njit = _njit_no_cache
numba.vectorize = _vectorize_no_cache
numba.guvectorize = _guvectorize_no_cache

import librosa  # noqa: E402


def run_vad(audio: np.ndarray, sr: int, model, utils) -> list[tuple[float, float]]:
    get_speech_ts, _, _, _, _ = utils

    tensor = torch.FloatTensor(audio)
    speeches = get_speech_ts(
        tensor,
        model,
        sampling_rate=sr,
        threshold=0.4,
        min_speech_duration_ms=80,
        min_silence_duration_ms=30,
    )
    segments = []
    for segment in speeches:
        start_ms = round(segment["start"] / sr * 1000, 1)
        end_ms = round(segment["end"] / sr * 1000, 1)
        segments.append((start_ms, end_ms))
    return segments


def run_flux(audio: np.ndarray, sr: int) -> list[tuple[float, str, float]]:
    hop_length = int(sr * 0.01)
    onset_env = librosa.onset.onset_strength(y=audio, sr=sr, hop_length=hop_length)
    max_val = onset_env.max()
    if max_val > 0:
        onset_env = onset_env / max_val

    frames = librosa.onset.onset_detect(
        onset_envelope=onset_env,
        sr=sr,
        hop_length=hop_length,
        backtrack=False,
        units="frames",
        delta=0.3,
    )

    results = []
    for frame in frames:
        time_ms = round(frame * hop_length / sr * 1000, 1)
        score = float(onset_env[frame])
        results.append((time_ms, "onset", score))
    return results


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("input")
    parser.add_argument("--vad", required=True)
    parser.add_argument("--flux", required=True)
    args = parser.parse_args()

    audio, sr = sf.read(args.input, dtype="float32", always_2d=False)
    if audio.ndim > 1:
        audio = audio.mean(axis=1)
    if sr != 16000:
        parser.error("A 16 kHz WAV is required; use Silence Retimes.bat to prepare it.")
    if audio.size == 0:
        parser.error("The WAV contains no audio samples.")

    torch.set_num_threads(1)

    model, utils = torch.hub.load(
        repo_or_dir="snakers4/silero-vad",
        model="silero_vad",
        force_reload=False,
        trust_repo=True,
    )
    vad_segments = run_vad(audio, sr, model, utils)
    with open(args.vad, "w", encoding="utf-8", newline="") as out:
        out.write("start_ms\tend_ms\r\n")
        for start, end in vad_segments:
            out.write(f"{start}\t{end}\r\n")

    flux_events = run_flux(audio, sr)
    with open(args.flux, "w", encoding="utf-8", newline="") as out:
        out.write("time_ms\ttype\tscore\r\n")
        for time_ms, event_type, score in flux_events:
            out.write(f"{time_ms}\t{event_type}\t{score}\r\n")


if __name__ == "__main__":
    main()
