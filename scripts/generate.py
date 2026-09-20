"""Shared entry points for the Chrono Generators batch files."""

import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent
VIDEO_EXTENSIONS = ('.mkv', '.mp4', '.avi', '.mov', '.ts', '.m4v', '.webm')
PRE_FILTER = 'highpass=f=80,lowpass=f=8000,dynaudnorm=f=150:g=5'


def tool(name):
    local = ROOT / (name + '.exe')
    found = str(local) if local.is_file() else shutil.which(name)
    if not found:
        raise RuntimeError(f'Missing {name}. Put the executable beside the batch files or on PATH.')
    return found


def run(command, **kwargs):
    result = subprocess.run(command, stderr=subprocess.PIPE, **kwargs)
    if result.returncode:
        error = result.stderr
        if isinstance(error, bytes):
            error = error.decode('utf-8', errors='replace')
        raise RuntimeError(f'{Path(command[0]).name}: {(error or "failed without details").strip()}')
    return result


def audio_stem(path):
    return re.sub(r'(?i)^vocals_|_vocals$', '', path.stem)


def find_audio(folder, stem):
    for name in (stem + '.wav', stem + '_vocals.wav', 'vocals_' + stem + '.wav'):
        path = folder / name
        if path.is_file():
            return path
    raise FileNotFoundError(f'Missing vocal WAV for {stem} in {folder}.')


def find_video(folder, stem):
    for extension in VIDEO_EXTENSIONS:
        path = folder / (stem + extension)
        if path.is_file():
            return path
    raise FileNotFoundError(f'Missing video for {stem} in {folder}.')


def numbered_input(number, operation):
    for stem in dict.fromkeys((str(number), f'{number:02d}')):
        try:
            if operation in ('keyframes', 'all'):
                return find_video(Path.cwd(), stem)
            return find_audio(Path.cwd(), stem)
        except FileNotFoundError:
            pass
    raise FileNotFoundError(f'Episode {number}: no input found in {Path.cwd()}.')


def keyframes(video, output):
    ffmpeg, scxvid = tool('ffmpeg'), tool('SCXvid')
    command = [ffmpeg, '-hide_banner', '-nostdin', '-loglevel', 'error', '-i', str(video),
               '-an', '-f', 'yuv4mpegpipe', '-vf', 'scale=640:360', '-pix_fmt', 'yuv420p',
               '-fps_mode', 'passthrough', '-']
    with tempfile.TemporaryFile() as errors:
        with subprocess.Popen(command, stdout=subprocess.PIPE, stderr=errors) as decoder:
            try:
                run([scxvid, str(output)], stdin=decoder.stdout, stdout=subprocess.DEVNULL)
            finally:
                decoder.stdout.close()
                status = decoder.wait()
            if status:
                errors.seek(0)
                raise RuntimeError(errors.read().decode('utf-8', errors='replace').strip())
    if not output.is_file() or not output.stat().st_size:
        raise RuntimeError('SCXvid did not produce a keyframe file.')


def prepare_audio(audio, output):
    run([tool('ffmpeg'), '-hide_banner', '-nostdin', '-loglevel', 'error', '-y',
         '-i', str(audio), '-vn', '-ac', '1', '-ar', '16000', '-af', PRE_FILTER,
         '-c:a', 'pcm_s16le', str(output)], stdout=subprocess.DEVNULL)


def retimes(prepared, folder, stem):
    outputs = []
    for threshold in (30, 40, 50):
        output = folder / f'{stem}_Retimes_{threshold}.txt'
        result = run([tool('ffmpeg'), '-hide_banner', '-nostdin', '-i', str(prepared),
                      '-af', f'silencedetect=n=-{threshold}dB:d=0.03', '-f', 'null', '-'],
                     stdout=subprocess.DEVNULL)
        output.write_bytes(result.stderr)
        outputs.append(output)
    vad = folder / f'{stem}_Retimes_vad.tsv'
    flux = folder / f'{stem}_Retimes_flux.tsv'
    executable = ROOT / 'vadflux.exe'
    command = ([str(executable)] if executable.is_file()
               else [sys.executable, str(ROOT / 'scripts/vadflux.py')])
    run(command + [str(prepared), '--vad', str(vad), '--flux', str(flux)])
    for output in (vad, flux):
        if not output.is_file() or not output.stat().st_size:
            raise RuntimeError(f'VADFlux did not produce {output.name}.')
    return outputs + [vad, flux]


def spectral(prepared, output):
    from spectral import compute_features, read_wav, write_tsv

    sample_rate, audio = read_wav(prepared)
    write_tsv(output, compute_features(audio, sample_rate, 32.0, 10.0))


def envelope(audio, output):
    result = run([tool('ffmpeg'), '-hide_banner', '-nostdin', '-loglevel', 'error',
                  '-i', str(audio), '-vn', '-af',
                  'astats=metadata=1:reset=1,ametadata=print:key=lavfi.astats.Overall.RMS_level:file=-',
                  '-f', 'null', '-'], stdout=subprocess.PIPE, text=True, encoding='utf-8')
    time = None
    count = 0
    with output.open('w', encoding='utf-8', newline='\n') as target:
        for line in result.stdout.splitlines():
            match = re.search(r'pts_time:([\d.eE+-]+)', line)
            if match:
                time = match.group(1)
            elif line.startswith('lavfi.astats.Overall.RMS_level=') and time is not None:
                target.write(f'{time},{line.split("=", 1)[1]}\n')
                count += 1
    if not count:
        raise RuntimeError('The WAV produced no RMS measurements.')


def process(operation, source):
    source = source.resolve()
    if not source.is_file():
        raise FileNotFoundError(f'File not found: {source}.')
    video = None
    if operation == 'keyframes':
        if source.suffix.lower() not in VIDEO_EXTENSIONS:
            raise ValueError('Keyframe generation requires a video.')
        video, audio, stem = source, None, source.stem
    elif operation == 'all':
        if source.suffix.lower() in VIDEO_EXTENSIONS:
            video, stem = source, source.stem
            audio = find_audio(source.parent, stem)
        elif source.suffix.lower() == '.wav':
            audio, stem = source, audio_stem(source)
            video = find_video(source.parent, stem)
        else:
            raise ValueError('Generate All requires a video or its vocal WAV.')
    else:
        if source.suffix.lower() != '.wav':
            raise ValueError('This generator requires a vocal WAV.')
        audio, stem = source, audio_stem(source)

    print(f'Processing: {source.name}', flush=True)
    with tempfile.TemporaryDirectory(prefix='.chrono-', dir=source.parent) as temp:
        folder = Path(temp)
        outputs = []
        if video:
            output = folder / f'{stem}_keyframes.log'
            keyframes(video, output)
            outputs.append(output)
        if operation in ('retimes', 'spectral', 'all'):
            prepared = folder / 'prepared.wav'
            prepare_audio(audio, prepared)
            if operation in ('retimes', 'all'):
                outputs.extend(retimes(prepared, folder, stem))
            if operation in ('spectral', 'all'):
                output = folder / f'{stem}_Retimes_spectrum.tsv'
                spectral(prepared, output)
                outputs.append(output)
        if operation in ('waveform', 'all'):
            from waveform import export_waveform

            output = folder / f'{stem}.waveform.json'
            export_waveform(audio, output, 0, tool('ffmpeg'))
            outputs.append(output)
        if operation in ('envelope', 'all'):
            output = folder / f'{stem}_envelope.tsv'
            envelope(audio, output)
            outputs.append(output)
        for output in outputs:
            destination = source.parent / output.name
            os.replace(output, destination)
            print(f'Output: {destination}')


def build():
    with tempfile.TemporaryDirectory(prefix='.chrono-build-', dir=ROOT) as folder:
        run([sys.executable, '-m', 'PyInstaller', '--noconfirm', '--onefile', '--console',
             '--name', 'vadflux', '--distpath', folder, '--workpath', str(Path(folder) / 'work'),
             '--specpath', folder, '--collect-all', 'librosa', '--collect-all', 'torchaudio',
             str(ROOT / 'scripts/vadflux.py')])
        executable = Path(folder) / 'vadflux.exe'
        if not executable.is_file():
            raise RuntimeError('PyInstaller did not produce vadflux.exe.')
        os.replace(executable, ROOT / 'vadflux.exe')
    print(f'Output: {ROOT / "vadflux.exe"}')


def main():
    parser = argparse.ArgumentParser(description='Generate analysis files for Chrono Suite.')
    parser.add_argument('operation', choices=('keyframes', 'retimes', 'spectral', 'envelope', 'waveform', 'all', 'build'))
    parser.add_argument('files', nargs='*', type=Path)
    args = parser.parse_args()
    if args.operation == 'build':
        if args.files:
            parser.error('build does not accept input files.')
        try:
            build()
            return 0
        except (OSError, RuntimeError) as error:
            print(f'Error: {error}', file=sys.stderr)
            return 1
    failed = 0
    sources = args.files
    if not sources:
        try:
            start, end = int(input('Start: ')), int(input('End: '))
            if start < 0 or end < start:
                raise ValueError('The range must be ascending and nonnegative.')
        except (ValueError, EOFError) as error:
            print(f'Invalid range: {error}', file=sys.stderr)
            return 1
        sources = []
        for number in range(start, end + 1):
            try:
                sources.append(numbered_input(number, args.operation))
            except FileNotFoundError as error:
                print(f'Error: {error}', file=sys.stderr)
                failed += 1
    seen = set()
    for source in sources:
        source = source.resolve()
        key = (source.parent, audio_stem(source) if source.suffix.lower() == '.wav' else source.stem)
        if args.operation == 'all' and key in seen:
            continue
        try:
            process(args.operation, source)
            seen.add(key)
        except (OSError, ValueError, RuntimeError, ImportError) as error:
            print(f'Error: {error}', file=sys.stderr)
            failed += 1
    print('Done.' if not failed else f'Finished with {failed} error(s).')
    return int(failed > 0)


if __name__ == '__main__':
    raise SystemExit(main())
