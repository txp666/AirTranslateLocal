import SwiftUI

struct SidebarView: View {
    @Bindable var session: TranslationSessionStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "waveform.bubble.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.tint)
                    Text(AppText.appName).font(.headline)
                    Text(LocalUI.text("本地翻译 · 不保存记录", "Local translation · No saved history"))
                        .font(.caption).foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Label(AppText.languages, systemImage: "globe").font(.headline)
                    Picker(AppText.from, selection: Binding(
                        get: { session.sourceLanguage },
                        set: { if !isLocked { session.useQuickSourceLanguage($0) } }
                    )) {
                        ForEach(LanguageOption.supported) { language in
                            Text(language.localizedTitle).tag(language)
                        }
                    }
                    Picker(AppText.to, selection: Binding(
                        get: { session.targetLanguage },
                        set: { if !isLocked { session.useQuickTargetLanguage($0) } }
                    )) {
                        ForEach(LanguageOption.supported.filter { $0 != session.sourceLanguage }) { language in
                            Text(language.localizedTitle).tag(language)
                        }
                    }
                    Button(AppText.swapLanguages, systemImage: "arrow.up.arrow.down") {
                        session.swapQuickLanguagePair()
                    }
                    .controlSize(.small)
                }
                .disabled(isLocked)

                VStack(alignment: .leading, spacing: 12) {
                    Label(AppText.audioInputSource, systemImage: "waveform").font(.headline)
                    Picker(AppText.audioInputSource, selection: $session.audioInputSource) {
                        ForEach(AudioInputSource.allCases) { source in
                            Text(source.title).tag(source)
                        }
                    }
                    .pickerStyle(.segmented).labelsHidden()
                    if session.audioInputSource == .microphone {
                        Picker(AppText.microphoneInputDevice, selection: $session.selectedMicrophoneInputDeviceID) {
                            ForEach(session.microphoneInputDevices) { device in
                                Text(device.name).tag(device.id)
                            }
                        }
                    }
                }
                .disabled(isLocked)

                Divider()
                LocalModelStatusView(session: session)
                if session.speechAvailability.state != .installed {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(session.speechAvailability.detail)
                            .font(.caption).foregroundStyle(.secondary)
                        if session.speechAvailability.state.canDownload {
                            Button(LocalUI.text("下载语音语言包", "Download speech pack")) {
                                session.downloadSpeechAssets()
                            }
                            .disabled(isLocked)
                        }
                    }
                }
            }
            .padding(18)
        }
        .onAppear {
            session.refreshSpeechAvailability()
            if !isLocked { session.refreshMicrophoneInputDevices() }
        }
    }

    private var isLocked: Bool {
        SidebarSessionConfigurationAccess.isLocked(isRunning: session.isRunning, isStarting: session.isStarting)
    }
}

struct LocalModelStatusView: View {
    @Bindable var session: TranslationSessionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(LocalUI.text("本地模型", "Local model"), systemImage: "desktopcomputer")
                .font(.headline)
            switch session.localModelRuntimeState {
            case .ready:
                switch session.localTranslationConnectionState {
                case .available:
                    Label(LocalUI.text("已就绪", "Ready"), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .checking:
                    Text(AppText.localTranslationChecking).font(.caption).foregroundStyle(.secondary)
                case .unchecked:
                    Text(LocalUI.text("模型设置已更改，请加载所选模型。", "Model settings changed. Load the selected model."))
                        .font(.caption).foregroundStyle(.secondary)
                    reconnectButton
                case let .unavailable(message):
                    Text(message).font(.caption).foregroundStyle(.secondary)
                    reconnectButton
                }
            case .preparing, .starting:
                HStack(alignment: .top, spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(session.localModelRuntimeState == .preparing
                         ? LocalUI.text("正在准备环境与模型，首次下载可能需要较长时间。", "Preparing the environment and model. The first download may take a while.")
                         : LocalUI.text("正在加载模型…", "Loading model…"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button(AppText.cancel) { session.cancelLocalModelPreparation() }
                    .controlSize(.small)
            case .stopped:
                Text(LocalUI.text("首次使用需要准备本地环境与模型。", "Prepare the local environment and model before first use."))
                    .font(.caption).foregroundStyle(.secondary)
                preparationActions
            case let .failed(message):
                Text(message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                preparationActions
            }
        }
    }

    private var reconnectButton: some View {
        Button(LocalUI.text("加载／重新连接", "Load / reconnect")) { session.prepareLocalModel() }
            .disabled(session.isRunning || session.isStarting)
    }

    private var preparationActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(LocalUI.text("准备本地模型", "Prepare local model")) {
                session.installLocalModel()
            }
            .buttonStyle(.borderedProminent)
            Button(LocalUI.text("已安装，重新连接", "Already installed? Reconnect")) {
                session.prepareLocalModel()
            }
            .buttonStyle(.link)
            Text(LocalUI.text("首次准备会联网安装依赖并下载所选模型（数 GB）；准备好后可离线翻译。", "Initial setup installs dependencies and downloads the selected model (several GB). Translation can then work offline."))
                .font(.caption2).foregroundStyle(.secondary)
        }
        .disabled(session.isRunning || session.isStarting)
    }
}

enum SidebarSessionConfigurationAccess {
    static func isLocked(isRunning: Bool, isStarting: Bool) -> Bool {
        isRunning || isStarting
    }
}
