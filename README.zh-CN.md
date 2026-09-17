# AirTranslate Local

[English](README.md)

面向 Apple Silicon Mac 的本地实时翻译和悬浮字幕。捕获系统播放音频或麦克风音频，使用 Apple Speech 识别，再交给本机 MLX 模型翻译。

界面只保留源语言、目标语言、音频输入、开始/停止和字幕选项。此版本不提供云翻译账号、API Key、配音或历史记录库。主界面与悬浮字幕使用同一份译文结果。

## 环境要求

- Apple Silicon Mac，macOS 26 或更新版本。
- 源码构建需要包含 Swift 6.2 或更新版本的 Xcode。
- 本地模型运行环境需要 Python 3.11 或更新版本。
- 首次安装 Python 依赖、模型权重和 Apple Speech 语言资源需要联网。
- 为模型预留磁盘和可用内存。默认 `mlx-community/Hy-MT2-7B-8bit` 的权重约 8 GB，运行时还需要额外内存。详见[模型指南](docs/local-mlx.md)。

## 首次使用

在本仓库的源码目录执行：

```bash
./script/build_and_run.sh
```

打开应用后点击 **准备本地模型**，明确执行运行环境安装和所选模型下载。新安装使用 `~/Library/Application Support/AirTranslate/LocalMLX/.venv`，已有开发环境可以复用。应用不会代为安装 Python；如果提示缺少 Python，请先安装 Python 3.11+ 后重试。

1. 准备本地模型并等待就绪。
2. 选择源语言、目标语言和音频输入。
3. 点击 **开始翻译**，按提示授予系统音频/屏幕录制和语音识别权限。只有使用麦克风输入时才需要麦克风权限。
4. 播放需要翻译的内容。开始翻译时自动打开悬浮字幕，显示样式可在设置中调整。点击 **停止** 结束采集，不保存历史记录。

首次识别某种语言时，按提示下载 Apple Speech 语言资源。修改 macOS 隐私权限后，请退出并重新打开应用。

普通模型启动仅使用已缓存文件，采用离线模式。缺少运行环境或模型时需要明确执行准备步骤，不会在采集过程中悄悄下载。开发者也可以执行 `./script/setup_local_mlx.sh --download-model`。更多说明见[本地模型安装与排错](docs/local-mlx.md)。

## 构建与验证

```bash
swift test
./script/verify_packaging_permissions.sh
./script/build_and_run.sh --build
./Release/build_open_source_release.sh all
```

开发应用位于 `dist/AirTranslate Local.app`，本地发布产物位于 `Release/product/`。安装包包含应用及安装辅助脚本，不包含 Python 或模型权重。未指定签名身份时使用临时签名，这些本地产物未经公证。详见[打包说明](Release/README.md)。

应用名称为 **AirTranslate Local**。默认 Bundle ID 保持 `com.txp.AirTranslateLocal`，兼容已有本地 macOS 权限。维护自己的分支时，可通过构建环境覆盖 `DISPLAY_NAME`、`APP_BUNDLE_NAME`、`ARTIFACT_NAME` 和 `BUNDLE_ID`；修改 Bundle ID 后需要重新授权。SwiftPM 可执行目标名称仍为 `AirTranslate`。

## 隐私

音频通过 Apple Speech 处理，识别出的文本只发送到配置的本机回环 MLX 接口。应用不调用云翻译 API，不保存音频，也不维护转写历史。设置和模型文件留在本机；运行诊断仅保存在内存中，可从设置查看。首次安装会联系 Python 软件包/模型托管服务，以及 Apple 资源下载服务。详见[隐私说明](Release/PRIVACY-NOTICE.md)。

## 来源与许可证

本项目修改自 [himomohi/AirTranslate](https://github.com/himomohi/AirTranslate)。此链接用于原项目署名，不是本地精简版的下载入口。构建脚本和 CI 只生成、验证产物，不推送标签、不发布 Release。

应用源码采用 [Apache 2.0](LICENSE)，原作者署名保留在 [NOTICE](NOTICE)。MLX LM 与模型权重为独立依赖，各自遵循对应许可证。详见[依赖许可证](docs/local-mlx.md#licenses)。

[贡献说明](CONTRIBUTING.md) · [安全说明](SECURITY.md) · [变更记录](CHANGELOG.md)
