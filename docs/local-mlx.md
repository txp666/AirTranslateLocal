# Local model setup

AirTranslate Local uses Apple Speech for recognition and a loopback MLX server for translation. Model weights and Python packages are installed separately from the app bundle.

## Install once

Use an Apple Silicon Mac, macOS 26+, and Python 3.11+. Open AirTranslate Local and choose **Prepare Local Model** / **准备本地模型**. Wait for the model to become ready, then choose your languages/input and press **Start translating** / **开始翻译**. The floating window opens automatically.

For development or terminal-based setup, run this optional command from the source checkout:

```bash
./script/setup_local_mlx.sh --download-model
```

This installs the tested `mlx-lm==0.31.3` runtime and explicitly downloads the default model. The default environment is `~/Library/Application Support/AirTranslate/LocalMLX/.venv`. Model files use the Hugging Face cache; `HF_HOME` can select a different cache location. A first download can take substantially longer than an ordinary model startup.

To choose the base Python interpreter:

```bash
AIRTRANSLATE_BOOTSTRAP_PYTHON="$(command -v python3)" \
  ./script/setup_local_mlx.sh --download-model
```

To reuse an existing project virtual environment:

```bash
./script/setup_local_mlx.sh --python "$PWD/.venv/bin/python" --download-model
```

A release bundle contains the same helper. The normal first-use path is its **Prepare Local Model** button. For terminal diagnostics, with the app installed at its default location, run:

```bash
bash "/Applications/AirTranslate Local.app/Contents/Resources/setup_local_mlx.sh" --download-model
```

Keep one installed copy when granting macOS privacy permissions. The default bundle identifier is `com.txp.AirTranslateLocal`; the runtime path deliberately retains `AirTranslate` for compatibility with earlier local builds.

## Model choice and offline startup

The default is [`mlx-community/Hy-MT2-7B-8bit`](https://huggingface.co/mlx-community/Hy-MT2-7B-8bit), an MLX conversion of Tencent's Hy-MT2 translation model. Its listed weight size is approximately 7.97 GB. That is a download size, not a RAM requirement or a promised translation speed. Leave additional disk space and memory for dependencies, loading, and macOS.

The smaller [`Hy-MT2-7B-4bit`](https://huggingface.co/mlx-community/Hy-MT2-7B-4bit) variant can be installed explicitly:

```bash
./script/setup_local_mlx.sh --model mlx-community/Hy-MT2-7B-4bit --download-model
```

Set the same model ID in the app's model settings. Other MLX-compatible models may need different prompts or generation settings and are not automatically equivalent to the default.

Check an installed runtime and cached model without downloading:

```bash
./script/setup_local_mlx.sh --check
```

Normal application/manual server startup sets `HF_HUB_OFFLINE=1` and `TRANSFORMERS_OFFLINE=1`. Only the setup/download step accesses the model host. The setup script pins the MLX LM version; dependency resolution and a model repository's latest revision can still change. For reproducible deployments, retain the installed dependency versions and downloaded snapshot revision alongside the build.

The app starts and warms up a compatible server automatically. It reuses an already-running compatible loopback service. A process started by the app is stopped when the app exits; a watchdog also handles app crashes. A manually started server remains under the terminal user's control:

```bash
./script/start_local_mlx.sh
```

`AIRTRANSLATE_LOCAL_PYTHON` selects a Python runtime, `AIRTRANSLATE_LOCAL_MODEL` selects a model, and `AIRTRANSLATE_LOCAL_PORT` selects a port for the manual helper. The default API endpoint is `http://127.0.0.1:8080/v1`; the app only accepts loopback hosts. Do not expose the model service to other machines.

## Troubleshooting

- **Python missing:** install Python 3.11+ and rerun setup; the helper does not install Homebrew or Python.
- **Runtime/model missing:** rerun the explicit setup command with `--download-model`; ordinary startup stays offline.
- **Incompatible Python override:** if `AIRTRANSLATE_LOCAL_PYTHON` points to an incomplete or outdated environment, repair that environment or unset the variable before preparing the standard runtime.
- **Model not served:** make the app's model ID match the server's model ID and check whether another program uses port 8080.
- **No transcript:** check audio input, macOS capture/speech permissions, and source-language Apple Speech assets.
- **Slow translation:** close memory-heavy applications or evaluate a smaller model. The current HTTP response arrives when each translated segment is complete.
- **Diagnostics:** open **Settings > Model diagnostics** / **设置 > 模型诊断日志**. Runtime output is held in memory instead of a persistent log file. Remove private text and paths before sharing any excerpt.

## Licenses

The application's [Apache-2.0 license](../LICENSE) and [original attribution](../NOTICE) cover its source code. They do not replace third-party dependency notices.

- [MLX LM](https://github.com/ml-explore/mlx-lm/blob/main/LICENSE) is MIT licensed; MLX is a separate runtime dependency.
- [Tencent Hy-MT2](https://github.com/Tencent-Hunyuan/Hy-MT2/blob/main/LICENSE.txt) supplies the upstream model license. The [Tencent model card](https://huggingface.co/tencent/Hy-MT2-7B) and the selected MLX conversion currently identify Apache-2.0.
- Python and the packages installed into the virtual environment retain their own licenses. They are not copied into the application bundle by the release script.

Review the license of each model you select. The release artifacts do not redistribute model weights or the Python environment.
