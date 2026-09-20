# Chrono Generators

These tools prepare the audio and scene data that [Chrono Suite](https://github.com/Kiterowx/Kite-Aegisub-Scripts/blob/main/docs/ChronoSuite.md) reads in Aegisub. The video supplies candidate scene cuts; a separated vocal track supplies the dialogue measurements. The generators write supporting files and leave the subtitle untouched.

## Start with a vocal track

A **vocal track**, or **vocal stem**, is the **Vocals** output from an audio separator. It may contain dialogue, singing, breaths, and several speakers at once. It does not contain a transcript or separate each character into their own track.

For an episode, keep `01.mkv`, `01.wav`, and `01.ass` together. The WAV must come from the **same edit**, start at the same point on the timeline, and retain the original speed and silences. Keep the original mix for checking quiet consonants, whispers, and word endings that separation may weaken. Some music can survive the process, and some speech can be lost.

## Requirements

| Task | Requirements |
| --- | --- |
| Run the batch files | Windows and 64-bit Python 3.10 or later, with versions supported by the chosen dependencies. |
| Process audio or decode video | [FFmpeg](https://ffmpeg.org/download.html). Put `ffmpeg.exe` beside the batch files or on PATH. The inspection examples also use FFprobe. |
| Generate keyframes, including Generate All | [SCXvid standalone](https://github.com/soyokaze/SCXvid-standalone/releases). Put `SCXvid.exe` beside the batch files or on PATH. It must accept YUV4MPEG on standard input and a log path as its argument; the VapourSynth plugin is a different tool. |
| Generate spectral features, including Generate All | [requirements.txt](requirements.txt): NumPy. |
| Generate VAD and flux | [requirements-vad.txt](requirements-vad.txt): NumPy, PyTorch, torchaudio, librosa, SoundFile, and Numba; or a `vadflux.exe` built with those dependencies. |
| Build `vadflux.exe` (optional) | [requirements-build.txt](requirements-build.txt), which adds PyInstaller. |
| Separate vocals | One of the free tools described below, installed separately. |
| Apply the results | Aegisub and Chrono Suite. Busy and Legacy also require `kite.Timing`, available through DependencyControl. |

**Waveform JSON needs only Python and FFmpeg.** That is enough to prepare the input for Lazy. To set up all audio generators, run this in PowerShell from this folder:

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install --upgrade pip
.\.venv\Scripts\python.exe -m pip install -r requirements-vad.txt
```

For spectral features alone, install `requirements.txt`. For waveform or RMS output, creating the environment is enough. The batch files use `.venv\Scripts\python.exe` if it exists, otherwise `python` on PATH. Keep the `scripts/` folder with them.

VADFlux loads [Silero VAD through PyTorch Hub](https://github.com/snakers4/silero-vad). The first run downloads the model and its code; later runs reuse Torch's cache. Detection runs on the CPU. PyTorch and torchaudio must be compatible versions.

To build the optional executable:

```powershell
.\.venv\Scripts\python.exe -m pip install -r requirements-build.txt
& '.\Build VADFlux.bat'
```

Silence Retimes and Generate All use `vadflux.exe` when it is beside the batch files. Otherwise, they run `scripts/vadflux.py` with the same Python environment. The executable still downloads Silero on first use; the model weights are not bundled.

## Extract and separate the vocals

Inspect the video's audio streams, then extract the language you are subtitling:

```powershell
ffprobe -v error -select_streams a -show_entries stream=index,codec_name,channels,start_time:stream_tags=language,title -of json '01.mkv'
ffmpeg -n -i '01.mkv' -map 0:a:0 -vn -ac 2 -ar 44100 -c:a pcm_s16le '01_mix.wav'
```

`0:a:0` selects the first audio stream; `0:a:1` selects the second. Listen to confirm the language. **A WAV extracted from the video still contains the full mix.** It needs separation before it becomes a vocal stem. If the container declares an audio delay, preserve its relationship to the picture: matching durations do not establish sync.

### UVR: desktop interface

Download [Ultimate Vocal Remover](https://github.com/Anjok07/ultimatevocalremovergui). Its desktop installer includes its own Python runtime and dependencies.

1. Select `01_mix.wav` as the input and a separate output folder.
2. Choose a model that produces **Vocals**. Download it in the app if needed.
3. Select WAV output and process the file. If you export only one stem, choose **Vocals**, rather than **Instrumental** or **No Vocals**.
4. Listen to the result, then copy the vocal stem beside `01.mkv` as `01.wav`.

Choose a model based on the dialogue it preserves, especially whispers and consonants. A cleaner-sounding result can still erase the speech onset needed for timing.

### Demucs: command line

[Demucs](https://github.com/facebookresearch/demucs) separates vocals and accompaniment. The original repository is archived; install it in a separate environment. This example requires Python 3.11:

```powershell
py -3.11 -m venv .venv-demucs
.\.venv-demucs\Scripts\python.exe -m pip install torch==2.0.1 torchaudio==2.0.2 --index-url https://download.pytorch.org/whl/cpu
.\.venv-demucs\Scripts\python.exe -m pip install 'numpy<2' soundfile 'demucs==4.0.1'
.\.venv-demucs\Scripts\python.exe -m demucs -n htdemucs --two-stems=vocals -d cpu -o separated '01_mix.wav'
Copy-Item -LiteralPath '.\separated\htdemucs\01_mix\vocals.wav' -Destination '.\01.wav'
```

The [PyTorch/torchaudio pair](https://pytorch.org/get-started/previous-versions/#v201) fits Demucs 4.0.1's `torchaudio<2.1` requirement; NumPy stays on 1.x. FFmpeg and FFprobe must be on PATH. The first separation downloads the model. `-d cpu` works without a compatible GPU, though runtime and memory use depend on the machine. `--two-stems=vocals` still separates the sources before combining the accompaniment; it does not guarantee lower memory use.

### Audio Separator

[Audio Separator](https://github.com/nomadkaraoke/python-audio-separator) runs UVR models and other architectures from the command line. Install it separately with `python -m pip install "audio-separator[cpu]"`; use `audio-separator --list_models` to browse the catalog. Choose a model with a Vocals output and export WAV. The [vocal preparation guide](https://kiterowx.github.io/Arquitectura-del-Timing/tecnica/vocales/) includes a complete example and sync checks.

## Choose the files you need

| Batch file | Input | Output for `01` | Use |
| --- | --- | --- | --- |
| `SCXvid Keyframes.bat` | `01.mkv` | `01_keyframes.log` | External keyframes in Aegisub; check the detected cuts against the picture. |
| `Waveform JSON.bat` | `01.wav` | `01.waveform.json` | Auto Timing → Lazy; optional waveform input for Busy; ChronoSplit and SubWave. |
| `Silence Retimes.bat` | `01.wav` | `01_Retimes_30.txt`, `_40.txt`, `_50.txt`, `_vad.tsv`, `_flux.tsv` | Silence logs for Legacy; silence, VAD, and flux for Busy. |
| `RMS Envelope.bat` | `01.wav` | `01_envelope.tsv` | Busy's RMS/dB envelope field. |
| `Spectral Features.bat` | `01.wav` | `01_Retimes_spectrum.tsv` | Reference data. Auto Timing does not load this file. |
| `Generate All.bat` | Video or its matching WAV | All nine files above | Full preparation; requires both inputs and all generation dependencies. |

Silence files are FFmpeg logs with times in seconds. VAD and flux use millisecond columns. The envelope retains its existing format: comma-separated seconds and RMS dB, with no header, despite its `.tsv` extension. The spectrum uses tabs; `speech_p` is a heuristic score with no calibration as a probability. The waveform JSON stores min/max peaks at a 1 ms base resolution and progressively coarser levels. It contains no playable audio.

## Run a generator

Drag one or more files onto the matching batch file. You can also launch it from PowerShell. For example, with `media` and `Chrono Generators` in the same folder:

```powershell
& '.\Chrono Generators\Waveform JSON.bat' '.\media\01.wav'
& '.\Chrono Generators\Generate All.bat' '.\media\01.mkv'
```

With no arguments, the script asks for **Start** and **End** episode numbers and searches the console's current directory. It accepts `1` or `01`, keeps three-digit numbers intact, and preserves the name it finds: `1.wav` produces `1.waveform.json`. Avoid keeping both `1.wav` and `01.wav` for the same episode.

The exact aliases `01_vocals.wav` and `vocals_01.wav` also work; their output stem is `01`. The video must use that same stem. Files are not paired by partial matches.

A successful run replaces outputs with the same names beside the source material. Keep a copy if you want to compare separation models. If processing fails, the previous outputs remain in place. Check the final console message before loading them: an existing file may belong to an earlier run.

To skip the batch file's closing pause, call Python directly:

```powershell
.\.venv\Scripts\python.exe scripts/generate.py waveform 'C:\media\01.wav'
```

## Load the results in Auto Timing

The control names below match Chrono Suite's English interface.

1. Open `01.ass` and the video in Aegisub. Load `01.wav` to hear the separated voices. Use **Video → Open Keyframes** to load `01_keyframes.log` when working with those cuts.
2. Place the cues roughly over their dialogue and select a short passage. Auto Timing searches around existing times; it does not align an untimed script from scratch.
3. Open **Chrono Suite → Auto Timing**. Select **Lazy** and load `01.waveform.json` in **Waveform JSON**. Start with **Raw voice**, then listen to the proposed edges.
4. For **Busy**, open **Busy Files...** and assign the silence logs, VAD, flux, and envelope. The optional waveform JSON goes in the main dialog. Check that every path belongs to this episode. The spectrum file is not a VAD or flux input.
5. **Full + polish** detects speech and applies padding, chaining, and keyframe snaps. **Post current** applies that finishing pass to the current times. Both require keyframes loaded in Aegisub; **Raw voice** does not use them.
6. **Legacy...** opens a separate silence-based workflow without keyframes. It needs `kite.Timing` and has its own controls, separate from Lazy and Busy's mode selector.
7. Review `[TM-…]` or `[LZ …]` markers in **Effect**, then check playback against the original mix. Enable **Reload waveform cache** after regenerating the JSON.

The [Subtitle Timing Guide](https://kiterowx.github.io/Arquitectura-del-Timing/) covers padding, scene cuts, and manual review of exceptions.
