# AirTranslate Local v2.0.0

AirTranslate Local 的首个正式版本，专注于本地实时翻译与字幕。版本号与上游 AirTranslate 的发布序列区分。

[下载 v2.0.0 DMG](https://github.com/txp666/AirTranslateLocal/releases/download/v2.0.0/AirTranslate-Local.dmg) · [v2.0.0 发布页与 ZIP/校验值](https://github.com/txp666/AirTranslateLocal/releases/tag/v2.0.0) · [后续最新版](https://github.com/txp666/AirTranslateLocal/releases/latest)

| 安装包 | SHA-256 校验文件 |
| --- | --- |
| [AirTranslate-Local.dmg](https://github.com/txp666/AirTranslateLocal/releases/download/v2.0.0/AirTranslate-Local.dmg) | [AirTranslate-Local.dmg.sha256](https://github.com/txp666/AirTranslateLocal/releases/download/v2.0.0/AirTranslate-Local.dmg.sha256) |
| [AirTranslate-Local-2.0.0-200.zip](https://github.com/txp666/AirTranslateLocal/releases/download/v2.0.0/AirTranslate-Local-2.0.0-200.zip) | [AirTranslate-Local-2.0.0-200.zip.sha256](https://github.com/txp666/AirTranslateLocal/releases/download/v2.0.0/AirTranslate-Local-2.0.0-200.zip.sha256) |

## 本次变化

- 使用 Apple Speech 识别系统音频或麦克风输入，再由本机 MLX 模型翻译；界面保留语言、音频输入、开始/停止及字幕设置。
- 移除云翻译配置、API Key、配音和历史记录库。应用不保存音频或转写历史；旧版已经保存的文件不会被删除。
- 主界面和悬浮字幕使用同一份已接受译文，修复译文更新或修订后两处内容不一致的问题。双语字幕使用与译文对应的原文片段。
- 按窗口实际宽度和字号保留最新字幕行，改善窄窗口、大字号及中英文混排的末尾显示。
- 修复取消启动后无法重新开始，以及过期启动回调覆盖当前状态的问题；取消准备和退出应用时清理应用拥有的模型子进程。
- 增加明确的“准备本地模型”操作，检查模型缓存与运行依赖，并支持重试修复中断的受管理环境安装。普通启动仅使用本地缓存。

## 系统要求

- Apple Silicon Mac，macOS 26 或更新版本。
- Python 3.11 或更新版本，用于单独安装的 MLX 环境；应用不会自动安装 Python。
- 首次安装依赖、下载模型及 Apple Speech 语言资源需要联网。
- 默认模型为 `mlx-community/Hy-MT2-7B-8bit`，权重约 8 GB；运行还需要额外内存和磁盘空间。详见[模型指南](https://github.com/txp666/AirTranslateLocal/blob/v2.0.0/docs/local-mlx.md)。

安装包不包含 Python 环境或模型权重。使用发布包不需要 Xcode；源码构建需要 Swift 6.2 或更新版本。

## 下载后使用

1. 打开 DMG，将 **AirTranslate Local.app** 拖入 **Applications（应用程序）**，推出磁盘映像，再打开应用。也可解压 ZIP 后将应用移入 Applications。
2. 本版本使用临时签名，**未经 Apple 公证**。若 macOS 阻止打开，且你信任来源，先尝试启动，再到 **系统设置 > 隐私与安全性 > 仍要打开（Open Anyway）**，仅为该应用添加例外。参见 [Apple 官方说明](https://support.apple.com/en-us/102445)。
3. 点击 **准备本地模型**，等待依赖安装和模型下载完成。如果提示缺少 Python，请先安装 Python 3.11+ 后重试。
4. 选择原文/译文语言与音频输入，点击 **开始翻译**，按提示授予音频采集和语音识别权限。麦克风权限仅在使用麦克风输入时需要。
5. 播放音频或对麦克风说话，悬浮字幕会自动打开。点击 **停止** 结束采集；诊断信息可在 **设置 > 模型诊断日志** 查看，仅保存在内存中。

将校验文件与对应安装包放在同一目录，在该目录执行对应命令检查完整性：

```bash
# DMG
shasum -a 256 -c AirTranslate-Local.dmg.sha256

# ZIP
shasum -a 256 -c AirTranslate-Local-2.0.0-200.zip.sha256
```

应用源码沿用 Apache 2.0，并保留原项目署名。MLX LM 和模型权重遵循各自的许可证。源码构建和打包步骤见[发布指南](https://github.com/txp666/AirTranslateLocal/blob/v2.0.0/Release/README.md)。
