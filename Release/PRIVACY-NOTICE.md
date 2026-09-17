# AirTranslate Local privacy notice

AirTranslate Local captures audio only while a translation session is running. The user chooses system audio or a microphone. Audio enters Apple Speech recognition; the resulting text is translated by an MLX model on the same Mac through a loopback HTTP endpoint.

The app has no account system, hosted translation integration, advertising, analytics SDK, or telemetry upload. There is no translated speech output or saved-transcript library. It does not write audio recordings or automatically save session transcripts. Removing the history feature does not delete files created by an older installation.

## Files and network access

- Preferences store language, audio-input, model, and caption settings locally.
- Python packages and model weights are installed separately, with an explicit setup/download step. That step contacts package indexes and the selected model host.
- Apple manages required Speech language assets and the associated initial downloads.
- Normal MLX server startup uses cached model files with offline environment settings.
- Runtime diagnostics are held in memory and shown under **Settings > Model diagnostics**. Treat diagnostic output as private and redact it before sharing; dependency errors can include local paths or request details. The app does not write a persistent runtime log.
- The app only accepts loopback model endpoints (`127.0.0.1`, `localhost`, or `::1`). A manually configured third-party service has its own behavior.

## Permissions

System-audio capture uses ScreenCaptureKit and macOS screen/system-audio permissions. Speech recognition requires macOS speech permission and language support. Microphone permission is needed only when microphone input is selected. The app does not request Contacts, Calendar, Photos, Location, or Full Disk Access.

The application is an independent fork and is not affiliated with Apple, Tencent, or the original project's author. Application and dependency licenses are described in the [model guide](../docs/local-mlx.md#licenses).
