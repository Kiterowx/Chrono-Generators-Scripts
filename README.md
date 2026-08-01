# Chrono Generators

Archivos por lotes para generar señales de timing usadas por
[Chrono Suite](https://github.com/Kiterowx/Kite-Aegisub-Scripts/blob/main/docs/ChronoSuite.md)
y por la guía [Arquitectura del Timing](https://kiterowx.github.io/Arquitectura-del-Timing/).

## Requisitos

- Windows.
- FFmpeg y FFprobe en el PATH. Descarga oficial: <https://ffmpeg.org/download.html>.
- SCXvid.exe en el PATH o junto a los BAT para `Keyframes SCXvid.bat`.
- Python 3.10 o superior.
- NumPy para `Features Espectrales.bat`, `Waveform JSON.bat` y `Procesar Todo.bat`.
- `vadflux.exe` para `Retimes Silencios.bat` y `Procesar Todo.bat`.
- UVR para separar la voz antes de generar señales de diálogo. Repositorio oficial: <https://github.com/Anjok07/ultimatevocalremovergui>.

`Build VADFlux.bat` construye `vadflux.exe` para los flujos que necesitan VAD y flux.

## Archivos

- `Keyframes SCXvid.bat`: extrae cambios de escena a `_keyframes.log`.
- `Retimes Silencios.bat`: produce silencios, VAD y flux.
- `Features Espectrales.bat`: produce `_Retimes_spectrum.tsv`.
- `Envelope RMS.bat`: produce `_envelope.tsv`.
- `Waveform JSON.bat`: produce `.waveform.json`.
- `Procesar Todo.bat`: ejecuta el flujo completo.
- `Build VADFlux.bat`: compila `vadflux.exe`.
- `scripts/vadflux.py`: fuente usado por `Build VADFlux.bat`.

## Uso

Prepara cada episodio como un par con el mismo número: `1.mkv` para los keyframes y
`1.wav` para todas las señales vocales. `Keyframes SCXvid.bat` recibe el video;
`Retimes Silencios.bat`, `Features Espectrales.bat`, `Envelope RMS.bat` y
`Waveform JSON.bat` reciben el WAV vocal.

Arrastra el archivo que corresponde sobre cada BAT o ejecútalo sin argumentos para
procesar un rango numerado. `Procesar Todo.bat` empareja el video y el WAV por nombre:
extrae los keyframes del primero y genera todas las señales de audio desde el segundo.
Los nombres antiguos como `1_vocals.wav` se reconocen como respaldo, pero el formato
normal es `1.wav`.

Los resultados se escriben junto al archivo procesado. Los ejecutables locales,
señales generadas, logs y carpetas temporales quedan fuera del control de versión.
