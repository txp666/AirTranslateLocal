# AirTranslate Local

[简体中文](README.zh-CN.md)

Local live translation and floating captions for Apple Silicon Macs. Capture system audio or a microphone, recognize speech with Apple Speech, and translate the text with a local MLX model.

The interface focuses on source/target languages, audio input, Start/Stop, and floating captions. This fork has no cloud translation accounts, API-key setup, dubbing, or saved-transcript library. The main workspace and floating captions use the same translation results.

## Requirements

- Apple Silicon Mac running macOS 26 or later.
- Xcode with Swift 6.2 or later to build from source.
- Python 3.11 or later for the separately installed MLX runtime.
- Internet access for the initial Python packages, model weights, and Apple Speech language assets.
- Disk space and available memory for your model. The default `mlx-community/Hy-MT2-7B-8bit` has approximately 8 GB of weights; runtime memory usage is additional. See the [model guide](docs/local-mlx.md).

## First setup

From a checkout of this repository:

```bash
./script/build_and_run.sh
```

Open the app and choose **Prepare Local Model**. This explicit step installs the runtime and downloads the selected model. New installations use `~/Library/Application Support/AirTranslate/LocalMLX/.venv`; existing development environments can be reused. If Python is missing, install Python 3.11+ and retry. Python is not installed automatically.

1. Prepare the local model and wait until it is ready.
2. Choose the source and target languages and the audio input.
3. Press **Start translating** and grant the requested system-audio/screen-recording and speech-recognition permissions. Microphone permission is needed only for microphone input.
4. Play the audio you want to translate. Floating captions open automatically when translation starts; their appearance is adjustable in Settings. **Stop** ends capture without saving a transcript.

Download the source language's Apple Speech assets when prompted. After changing macOS privacy permissions, quit and relaunch the app.

The normal model startup uses cached files in offline mode. A missing runtime or model needs the explicit preparation step; it is not silently downloaded during capture. Developers can alternatively run `./script/setup_local_mlx.sh --download-model`. See [local model setup and troubleshooting](docs/local-mlx.md).

## Build and verify

```bash
swift test
./script/verify_packaging_permissions.sh
./script/build_and_run.sh --build
./Release/build_open_source_release.sh all
```

The development app is `dist/AirTranslate Local.app`. Local release artifacts are written to `Release/product/`. The bundle contains the app and setup helpers, not Python or model weights. Packaging uses ad-hoc signing unless you supply a signing identity; these local artifacts are not notarized. See [packaging instructions](Release/README.md).

The display name is **AirTranslate Local**, and the default bundle identifier remains `com.txp.AirTranslateLocal` to preserve existing local macOS permissions. A distributor can override `DISPLAY_NAME`, `APP_BUNDLE_NAME`, `ARTIFACT_NAME`, and `BUNDLE_ID` in the build environment. Changing the bundle identifier requires granting permissions again. The SwiftPM executable target remains `AirTranslate`.

## Privacy

Audio is processed through Apple Speech; recognized text is sent only to the configured loopback MLX endpoint. The app does not call a hosted translation API. It does not save audio or maintain transcript history. Preferences and model files remain on the Mac; runtime diagnostics are held in memory and shown in Settings. The first installation contacts Python package/model hosts and Apple services to obtain required assets. See the [privacy notice](Release/PRIVACY-NOTICE.md).

## Source and licenses

This is a modified fork of [himomohi/AirTranslate](https://github.com/himomohi/AirTranslate). The upstream link is an attribution, not a download location for this local edition. The scripts and CI only build and verify artifacts; they do not push tags or publish releases.

Application source is licensed under [Apache 2.0](LICENSE); original attribution is retained in [NOTICE](NOTICE). MLX LM and model weights are separate dependencies with their own licenses and notices. See [dependency licenses](docs/local-mlx.md#licenses).

[Contributing](CONTRIBUTING.md) · [Security](SECURITY.md) · [Changes](CHANGELOG.md)
