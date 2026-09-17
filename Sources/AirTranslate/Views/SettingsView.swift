import SwiftUI

struct SettingsView: View {
    @Bindable var session: TranslationSessionStore

    var body: some View {
        Form {
            Section(LocalUI.text("悬浮字幕", "Floating captions")) {
                Picker(LocalUI.text("显示内容", "Display"), selection: $session.floatingCaptionDisplayMode) {
                    ForEach(FloatingCaptionDisplayMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                Picker(LocalUI.text("字号", "Text size"), selection: $session.floatingCaptionTextSize) {
                    ForEach(FloatingCaptionTextSize.allCases) { size in Text(size.title).tag(size) }
                }
                Picker(LocalUI.text("行数", "Lines"), selection: $session.floatingCaptionLineCount) {
                    ForEach(FloatingCaptionLineCount.allCases) { count in Text(count.title).tag(count) }
                }
                Toggle(LocalUI.text("显示字幕背景", "Show caption background"), isOn: $session.showsFloatingCaptionBackground)
                Toggle(LocalUI.text("始终置顶", "Keep above other windows"), isOn: $session.keepsFloatingCaptionAboveOtherWindows)
            }

            Section(LocalUI.text("翻译模型", "Translation model")) {
                Picker(LocalUI.text("模型", "Model"), selection: $session.localTranslationModelID) {
                    Text("Hy-MT2 · 8-bit").tag(LocalTranslationConfiguration.defaultModelID)
                    Text("Hy-MT2 · 4-bit").tag("mlx-community/Hy-MT2-7B-4bit")
                    if !standardModelIDs.contains(session.localTranslationModelID) {
                        Text(session.localTranslationModelID).tag(session.localTranslationModelID)
                    }
                }
                .disabled(configurationLocked)
                Text(LocalUI.text("4-bit 占用更少内存；更换模型后需加载，首次使用新模型需点击准备。", "4-bit uses less memory. Load the model after changing it; use Prepare for a model you have not downloaded."))
                    .font(.caption).foregroundStyle(.secondary)
                LocalModelStatusView(session: session)
                DisclosureGroup(LocalUI.text("高级连接设置", "Advanced connection")) {
                    TextField(LocalUI.text("本机服务地址", "Local server URL"), text: $session.localTranslationBaseURLString)
                    TextField(LocalUI.text("模型名称或路径", "Model ID or path"), text: $session.localTranslationModelID)
                    Text(LocalUI.text("仅连接本机回环地址。自建兼容服务启动后，点击重新连接即可。", "Only loopback addresses are accepted. Start your compatible local server, then reconnect."))
                        .font(.caption).foregroundStyle(.secondary)
                    Button(LocalUI.text("重新连接", "Reconnect")) { session.prepareLocalModel() }
                }
                .disabled(configurationLocked)
            }

            Section(LocalUI.text("帮助", "Help")) {
                DisclosureGroup(LocalUI.text("系统权限", "macOS permissions")) {
                    Text(LocalUI.text("点击开始时会申请必要权限；如果之前拒绝过，可在系统设置中开启。", "Required permissions are requested when you start. If previously denied, enable them in System Settings."))
                        .font(.caption).foregroundStyle(.secondary)
                    Button(LocalUI.text("屏幕与系统音频录制", "Screen & system audio recording")) {
                        session.openPrivacySettings(.screenRecording)
                    }
                    Button(AppText.microphoneInput) { session.openPrivacySettings(.microphone) }
                    Button(LocalUI.text("语音识别", "Speech recognition")) {
                        session.openPrivacySettings(.speechRecognition)
                    }
                }
                DisclosureGroup(LocalUI.text("模型诊断日志", "Model diagnostics")) {
                    ScrollView {
                        Text(session.localModelRuntimeLog.isEmpty
                             ? LocalUI.text("暂无日志", "No log output yet") : session.localModelRuntimeLog)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 140)
                }
                Text(LocalUI.text("音频在本机识别，文字仅交给本机模型翻译。应用不保存会话历史；复制内容由你决定。", "Speech is recognized on this Mac and text is translated by a local model. The app does not save session history. You can copy text when needed."))
                    .font(.caption).foregroundStyle(.secondary)
                if let version = RunningAppVersion.current().summary {
                    LabeledContent(LocalUI.text("版本", "Version"), value: version)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 580, height: 620)
        .navigationTitle(AppText.settings)
    }

    private var standardModelIDs: [String] {
        [LocalTranslationConfiguration.defaultModelID, "mlx-community/Hy-MT2-7B-4bit"]
    }

    private var configurationLocked: Bool {
        session.isRunning || session.isStarting || session.localModelRuntimeState == .preparing || session.localModelRuntimeState == .starting
    }
}
