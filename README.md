# Chrono Generators

Archivos por lotes para generar señales de timing usadas por
[Chrono Suite](https://github.com/Kitherow/Kite-Aegisub-Scripts/blob/main/docs/ChronoSuite.md)
y por la guía [Arquitectura del Timing](https://kitherow.github.io/Arquitectura-del-Timing/).

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

Arrastra archivos de audio o video sobre el BAT correspondiente, o ejecuta el BAT
sin argumentos para procesar un rango numerado de episodios.

Los resultados se escriben junto al archivo procesado. Los ejecutables locales,
señales generadas, logs y carpetas temporales quedan fuera del control de versión.
