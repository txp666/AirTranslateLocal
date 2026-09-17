import Foundation

enum AppText {
    private enum InterfaceLanguage {
        case english
        case korean
        case japanese
        case chineseSimplified
    }

    private static var interfaceLanguage: InterfaceLanguage {
        let languageCode = Locale.preferredLanguages.first?.lowercased() ?? ""
        if languageCode.hasPrefix("ko") {
            return .korean
        }
        if languageCode.hasPrefix("ja") {
            return .japanese
        }
        if languageCode.hasPrefix("zh") {
            return .chineseSimplified
        }
        return .english
    }

    static func localized(english: String, korean: String) -> String {
        localized(
            english: english,
            korean: korean,
            japanese: english,
            chineseSimplified: english
        )
    }

    static func localized(
        english: String,
        korean: String,
        japanese: String,
        chineseSimplified: String
    ) -> String {
        switch interfaceLanguage {
        case .english:
            english
        case .korean:
            korean
        case .japanese:
            japanese
        case .chineseSimplified:
            chineseSimplified
        }
    }

    static let appName = "AirTranslate Local"
    static let settings = localized(english: "Settings", korean: "설정", japanese: "設定", chineseSimplified: "设置")
    static let quit = localized(english: "Quit", korean: "종료", japanese: "終了", chineseSimplified: "退出")
    static let ready = localized(english: "Ready", korean: "준비됨", japanese: "準備完了", chineseSimplified: "就绪")
    static let stopped = localized(english: "Stopped", korean: "중지됨", japanese: "停止中", chineseSimplified: "已停止")
    static let paused = localized(english: "Paused", korean: "일시정지됨", japanese: "一時停止中", chineseSimplified: "已暂停")
    static let capture = LocalUI.text("翻译", "Translation")
    static let start = LocalUI.text("开始翻译", "Start translating")
    static let stop = localized(english: "Stop", korean: "중지", japanese: "停止", chineseSimplified: "停止")
    static let cancel = localized(english: "Cancel", korean: "취소", japanese: "キャンセル", chineseSimplified: "取消")
    static let pause = localized(english: "Pause", korean: "일시정지", japanese: "一時停止", chineseSimplified: "暂停")
    static let resume = localized(english: "Resume", korean: "재개", japanese: "再開", chineseSimplified: "继续")
    static let languages = localized(english: "Languages", korean: "언어", japanese: "言語", chineseSimplified: "语言")
    static let from = localized(english: "From", korean: "원문", japanese: "原文", chineseSimplified: "原文")
    static let to = localized(english: "To", korean: "번역", japanese: "翻訳", chineseSimplified: "译文")
    static let swapLanguages = localized(english: "Swap Languages", korean: "언어 바꾸기", japanese: "言語を入れ替え", chineseSimplified: "交换语言")
    static let audioInputSource = localized(
        english: "Audio Input",
        korean: "오디오 입력",
        japanese: "オーディオ入力",
        chineseSimplified: "音频输入"
    )
    static let systemAudioInput = localized(
        english: "Mac Audio",
        korean: "PC 소리",
        japanese: "Mac音声",
        chineseSimplified: "Mac 音频"
    )
    static let microphoneInput = localized(
        english: "Microphone",
        korean: "마이크",
        japanese: "マイク",
        chineseSimplified: "麦克风"
    )
    static let microphoneInputDevice = localized(
        english: "Input Device",
        korean: "입력 장치",
        japanese: "入力デバイス",
        chineseSimplified: "输入设备"
    )
    static let systemDefaultMicrophone = localized(
        english: "System Default",
        korean: "시스템 기본값",
        japanese: "システム標準",
        chineseSimplified: "系统默认"
    )
    static let modelStatusChecking = localized(english: "Checking", korean: "확인 중", japanese: "確認中", chineseSimplified: "正在检查")
    static let modelStatusInstalled = localized(english: "Installed", korean: "설치됨", japanese: "インストール済み", chineseSimplified: "已安装")
    static let modelStatusDownloadRequired = localized(english: "Download Needed", korean: "다운로드 필요", japanese: "ダウンロードが必要", chineseSimplified: "需要下载")
    static let modelStatusDownloading = localized(english: "Downloading", korean: "다운로드 중", japanese: "ダウンロード中", chineseSimplified: "正在下载")
    static let modelStatusUnsupported = localized(english: "Unsupported", korean: "미지원", japanese: "未対応", chineseSimplified: "不支持")
    static let modelStatusUnavailable = localized(english: "Unavailable", korean: "사용 불가", japanese: "利用不可", chineseSimplified: "不可用")
    static let modelStatusFailed = localized(english: "Check Failed", korean: "확인 실패", japanese: "確認失敗", chineseSimplified: "检查失败")
    static let startBlockedLocalAssetsChecking = localized(english: "Still checking local language assets. Try again in a moment.", korean: "로컬 언어 자산을 아직 확인하는 중입니다. 잠시 후 다시 시작하세요.", japanese: "Still checking local language assets. Try again in a moment.", chineseSimplified: "正在检查本地语音包，请稍候。")
    static let startBlockedLocalAssetsDownloadRequired = localized(english: "Download the required language assets before starting.", korean: "시작하기 전에 필요한 언어 자산을 다운로드하세요.", japanese: "Download the required language assets before starting.", chineseSimplified: "请先下载所需的语音包。")
    static func startBlockedLocalAssetsUnavailable(_ detail: String) -> String {
        localized(english: "Required language assets are unavailable: \(detail)", korean: "필요한 언어 자산을 사용할 수 없습니다: \(detail)", japanese: "Required language assets are unavailable: \(detail)", chineseSimplified: "所需语音包不可用：\(detail)")
    }
    static let menuBarTitle = localized(english: "Captions", korean: "자막", japanese: "Captions", chineseSimplified: "字幕")
    static let menuBarRunningTitle = localized(english: "Live", korean: "기록 중", japanese: "Live", chineseSimplified: "翻译中")
    static let menuBarPausedTitle = localized(english: "Paused", korean: "일시정지", japanese: "Paused", chineseSimplified: "已暂停")
    static let floatingCaptions = localized(english: "Floating Captions", korean: "플로팅 자막", japanese: "フローティング字幕", chineseSimplified: "悬浮字幕")
    static let showFloatingCaptions = localized(
        english: "Show Floating Captions",
        korean: "플로팅 자막 보기",
        japanese: "フローティング字幕を表示",
        chineseSimplified: "显示悬浮字幕"
    )
    static let floatingCaptionPowerOn = localized(english: "ON", korean: "켜짐", japanese: "ON", chineseSimplified: "已开启")
    static let floatingCaptionPowerOff = localized(english: "OFF", korean: "꺼짐", japanese: "OFF", chineseSimplified: "已关闭")
    static let hideFloatingCaptions = localized(
        english: "Hide Floating Captions",
        korean: "플로팅 자막 숨기기",
        japanese: "フローティング字幕を隠す",
        chineseSimplified: "隐藏悬浮字幕"
    )
    static let originalOnly = localized(english: "Original Only", korean: "원문만", japanese: "原文のみ", chineseSimplified: "仅原文")
    static let originalAndTranslation = localized(english: "Original + Translation", korean: "원문 + 번역", japanese: "原文 + 翻訳", chineseSimplified: "原文 + 译文")
    static let translationOnly = localized(english: "Translation Only", korean: "번역만", japanese: "翻訳のみ", chineseSimplified: "仅译文")
    static let textSizeSmall = localized(english: "Small", korean: "작게", japanese: "小", chineseSimplified: "小")
    static let textSizeMedium = localized(english: "Medium", korean: "보통", japanese: "中", chineseSimplified: "中")
    static let textSizeLarge = localized(english: "Large", korean: "크게", japanese: "大", chineseSimplified: "大")
    static let textSizeExtraLarge = localized(english: "Extra Large", korean: "아주 크게", japanese: "特大", chineseSimplified: "特大")
    static let noFloatingCaptionsYet = localized(english: "Live captions will appear here.", korean: "실시간 자막이 여기에 표시됩니다.", japanese: "Live captions will appear here.", chineseSimplified: "实时字幕将在这里显示。")
    static let original = localized(english: "Original", korean: "원문", japanese: "原文", chineseSimplified: "原文")
    static let translation = localized(english: "Translation", korean: "번역", japanese: "翻訳", chineseSimplified: "译文")
    static let copy = localized(english: "Copy", korean: "복사", japanese: "Copy", chineseSimplified: "复制")
    static let copied = localized(english: "Copied", korean: "복사됨", japanese: "Copied", chineseSimplified: "已复制")
    static func copyTranscriptPane(_ title: String) -> String {
        localized(english: "Copy \(title)", korean: "\(title) 복사", japanese: "Copy \(title)", chineseSimplified: "复制\(title)")
    }
    static let checkingScreenPermission = localized(english: "Checking screen recording permission...", korean: "화면 기록 권한 확인 중...", japanese: "Checking screen recording permission...", chineseSimplified: "正在检查屏幕录制权限……")
    static let checkingMicrophonePermission = localized(english: "Checking microphone permission...", korean: "마이크 권한 확인 중...", japanese: "Checking microphone permission...", chineseSimplified: "正在检查麦克风权限……")
    static let checkingSpeechPermission = localized(english: "Checking speech recognition permission...", korean: "음성 인식 권한 확인 중...", japanese: "Checking speech recognition permission...", chineseSimplified: "正在检查语音识别权限……")
    static func startingCapture(for source: AudioInputSource) -> String {
        switch source {
        case .systemAudio:
            localized(english: "Starting Mac audio capture...", korean: "Mac 오디오 캡처 시작 중...", japanese: "Starting Mac audio capture...", chineseSimplified: "正在接入 Mac 音频……")
        case .microphone:
            localized(english: "Starting microphone capture...", korean: "마이크 캡처 시작 중...", japanese: "Starting microphone capture...", chineseSimplified: "正在接入麦克风……")
        }
    }
    static func listeningForSpeech(from source: AudioInputSource) -> String {
        switch source {
        case .systemAudio:
            localized(english: "Listening to Mac audio, waiting for speech...", korean: "Mac 오디오를 듣는 중, 음성을 기다리는 중...", japanese: "Listening to Mac audio, waiting for speech...", chineseSimplified: "正在监听 Mac 音频，等待语音……")
        case .microphone:
            localized(english: "Listening to microphone, waiting for speech...", korean: "마이크를 듣는 중, 음성을 기다리는 중...", japanese: "Listening to microphone, waiting for speech...", chineseSimplified: "正在监听麦克风，等待语音……")
        }
    }
    static let translating = localized(english: "Translating...", korean: "번역 중...", japanese: "Translating...", chineseSimplified: "正在翻译……")
    static let sameLanguageTranslationUnavailable = localized(english: "Choose different source and target languages to translate.", korean: "번역하려면 원문과 번역 언어를 다르게 선택하세요.", japanese: "Choose different source and target languages to translate.", chineseSimplified: "请选择不同的原文和译文语言。")
    static func lineCount(_ count: Int) -> String {
        localized(english: "\(count) lines", korean: "\(count)줄", japanese: "\(count) lines", chineseSimplified: "\(count) 行")
    }

    static func speechModelAvailabilityDetail(source: String, status: String) -> String {
        localized(english: "Source: \(source). Local asset: \(status).", korean: "원문: \(source). 로컬 자산: \(status).", japanese: "Source: \(source). Local asset: \(status).", chineseSimplified: "\(source)语音包：\(status)")
    }

    static let localTranslationChecking = localized(
        english: "Checking the local MLX translation server...",
        korean: "로컬 MLX 번역 서버를 확인하는 중입니다...",
        japanese: "ローカルMLX翻訳サーバーを確認しています...",
        chineseSimplified: "正在检查本地 MLX 翻译服务……"
    )
    static let localTranslationAvailable = localized(
        english: "Local MLX server is ready.",
        korean: "로컬 MLX 서버를 사용할 수 있습니다.",
        japanese: "ローカルMLXサーバーを使用できます。",
        chineseSimplified: "本地 MLX 服务已就绪。"
    )
    static let localModelRuntimeStarting = localized(
        english: "Starting and warming up the local MLX model...",
        korean: "로컬 MLX 모델을 시작하고 준비하는 중입니다...",
        japanese: "ローカルMLXモデルを起動してウォームアップしています...",
        chineseSimplified: "正在启动并预热本地 MLX 模型……"
    )
    static let localModelRuntimeNotFound = LocalUI.text(
        "本地模型尚未准备好，请点击“准备本地模型”。",
        "The local model is not set up yet. Click Prepare local model."
    )
    static let localModelRuntimeWatchdogNotFound = localized(
        english: "The local MLX lifecycle helper is missing from this AirTranslate build.",
        korean: "이 AirTranslate 빌드에 로컬 MLX 수명 주기 도우미가 없습니다.",
        japanese: "このAirTranslateビルドにはローカルMLXライフサイクルヘルパーがありません。",
        chineseSimplified: "当前 AirTranslate 构建缺少本地 MLX 生命周期辅助程序。"
    )
    static let localModelRuntimeUnsupportedConfiguration = localized(
        english: "Automatic model startup requires a loopback HTTP URL with an explicit port.",
        korean: "자동 모델 시작에는 포트가 명시된 루프백 HTTP URL이 필요합니다.",
        japanese: "モデルの自動起動には、ポートを明示したループバックHTTP URLが必要です。",
        chineseSimplified: "自动启动模型需要带明确端口的本机 HTTP 回环地址。"
    )
    static let localModelRuntimeStartFailed = localized(
        english: "AirTranslate could not start the local MLX model.",
        korean: "AirTranslate가 로컬 MLX 모델을 시작할 수 없습니다.",
        japanese: "AirTranslateはローカルMLXモデルを起動できませんでした。",
        chineseSimplified: "AirTranslate 无法启动本地 MLX 模型。"
    )
    static let localModelRuntimeReadinessTimedOut = localized(
        english: "The local MLX model did not become ready in time.",
        korean: "로컬 MLX 모델이 제한 시간 내에 준비되지 않았습니다.",
        japanese: "ローカルMLXモデルの準備が時間内に完了しませんでした。",
        chineseSimplified: "本地 MLX 模型未能在限定时间内就绪。"
    )
    static func localModelRuntimeExited(status: Int32) -> String {
        localized(
            english: "The local MLX model process exited (status \(status)).",
            korean: "로컬 MLX 모델 프로세스가 종료되었습니다(상태 \(status)).",
            japanese: "ローカルMLXモデルプロセスが終了しました（ステータス \(status)）。",
            chineseSimplified: "本地 MLX 模型进程已退出（状态 \(status)）。"
        )
    }
    static let localTranslationInvalidBaseURL = localized(
        english: "Enter a loopback MLX API URL such as http://127.0.0.1:8080/v1.",
        korean: "http://127.0.0.1:8080/v1 같은 루프백 MLX API URL을 입력하세요.",
        japanese: "http://127.0.0.1:8080/v1 のようなループバックMLX API URLを入力してください。",
        chineseSimplified: "请输入回环地址，例如 http://127.0.0.1:8080/v1。"
    )
    static let localTranslationEmptyModelID = localized(
        english: "Enter the local model ID.",
        korean: "로컬 모델 ID를 입력하세요.",
        japanese: "ローカルモデルIDを入力してください。",
        chineseSimplified: "请输入本地模型 ID。"
    )
    static let localTranslationModelUnavailable = localized(
        english: "The local MLX server is not serving the selected model.",
        korean: "로컬 MLX 서버에서 선택한 모델을 제공하지 않습니다.",
        japanese: "ローカルMLXサーバーは選択したモデルを提供していません。",
        chineseSimplified: "本地 MLX 服务没有加载所选模型。"
    )
    static let localTranslationConnectionFailed = LocalUI.text(
        "无法连接本地模型，请点击“重新连接”，或在设置中查看诊断日志。",
        "Could not connect to the local model. Reconnect, or check the diagnostic log in Settings."
    )
    static let localTranslationInvalidResponse = localized(
        english: "The local MLX server returned an invalid response.",
        korean: "로컬 MLX 서버가 올바르지 않은 응답을 반환했습니다.",
        japanese: "ローカルMLXサーバーから無効な応答が返されました。",
        chineseSimplified: "本地 MLX 服务返回了无效响应。"
    )
    static let localTranslationEmptyOutput = localized(
        english: "The local model returned no translated text.",
        korean: "로컬 모델이 번역 텍스트를 반환하지 않았습니다.",
        japanese: "ローカルモデルから翻訳テキストが返されませんでした。",
        chineseSimplified: "本地模型没有返回译文。"
    )

    static func localTranslationRequestFailed(statusCode: Int, message: String?) -> String {
        let safeMessage = message?
            .replacingOccurrences(of: "\n", with: " ")
            .prefix(240)
        let detail = safeMessage.map { ": \($0)" } ?? ""
        return localized(
            english: "Local MLX request failed (\(statusCode))\(detail)",
            korean: "로컬 MLX 요청 실패(\(statusCode))\(detail)",
            japanese: "ローカルMLXリクエストに失敗しました（\(statusCode)）\(detail)",
            chineseSimplified: "本地 MLX 请求失败（\(statusCode)）\(detail)"
        )
    }

    static let translationCancelled = localized(english: "Translation cancelled.", korean: "번역이 취소되었습니다.", japanese: "Translation cancelled.", chineseSimplified: "翻译已取消。")

    static func startFailed(_ message: String) -> String {
        localized(english: "Start failed: \(message)", korean: "시작 실패: \(message)", japanese: "Start failed: \(message)", chineseSimplified: "启动失败：\(message)")
    }

    static func receivingAudioWaiting(sampleCount: Int, source: AudioInputSource) -> String {
        listeningForSpeech(from: source)
    }

    static func receivingSilentAudio(sampleCount: Int, level: Int, source: AudioInputSource) -> String {
        switch source {
        case .systemAudio:
            LocalUI.text("暂未检测到声音，请确认 Mac 正在播放音频。", "No sound detected. Make sure your Mac is playing audio.")
        case .microphone:
            LocalUI.text("暂未检测到语音，请检查麦克风或靠近一些。", "No speech detected. Check your microphone or move closer.")
        }
    }

    static func receivingAudioTranscribing(sampleCount: Int, level: Int, source: AudioInputSource) -> String {
        LocalUI.text("正在识别语音……", "Recognizing speech…")
    }

    static let speechPermissionDenied = localized(english: "Speech recognition permission was not granted.", korean: "음성 인식 권한이 허용되지 않았습니다.", japanese: "Speech recognition permission was not granted.", chineseSimplified: "未获得语音识别权限，请在系统设置中允许。")
    static let recognizerUnavailable = localized(english: "The selected speech recognizer is unavailable.", korean: "선택한 음성 인식기를 사용할 수 없습니다.", japanese: "The selected speech recognizer is unavailable.", chineseSimplified: "所选语言的语音识别暂不可用。")
    static let screenRecordingNotGranted = localized(english: "Screen Recording permission is not active for this signed AirTranslate app. Grant it once, then quit and relaunch AirTranslate.", korean: "서명된 AirTranslate 앱에 화면 기록 권한이 활성화되어 있지 않습니다. 한 번 허용한 뒤 AirTranslate를 종료하고 다시 실행하세요.", japanese: "Screen Recording permission is not active for this signed AirTranslate app. Grant it once, then quit and relaunch AirTranslate.", chineseSimplified: "请在系统设置中允许 AirTranslate Local 录制屏幕与系统音频，然后重新打开软件。")
    static let microphoneNotGranted = localized(english: "Microphone permission is not active for this signed AirTranslate app. Grant it once, then quit and relaunch AirTranslate.", korean: "서명된 AirTranslate 앱에 마이크 권한이 활성화되어 있지 않습니다. 한 번 허용한 뒤 AirTranslate를 종료하고 다시 실행하세요.", japanese: "Microphone permission is not active for this signed AirTranslate app. Grant it once, then quit and relaunch AirTranslate.", chineseSimplified: "请在系统设置中允许 AirTranslate Local 使用麦克风，然后重新打开软件。")
    static let microphoneUnavailable = localized(english: "The microphone input could not be started.", korean: "마이크 입력을 시작할 수 없습니다.", japanese: "The microphone input could not be started.", chineseSimplified: "无法启动麦克风，请检查输入设备。")
    static let noActiveDisplay = localized(english: "No active display was available for system audio capture.", korean: "시스템 오디오 캡처에 사용할 수 있는 활성 디스플레이가 없습니다.", japanese: "No active display was available for system audio capture.", chineseSimplified: "无法捕获系统音频：未找到正在使用的显示器。")

    static func languageTitle(for id: String, fallback: String) -> String {
        switch id {
        case "en-US":
            localized(english: "English", korean: "영어", japanese: "英語", chineseSimplified: "英语")
        case "ko-KR":
            localized(english: "Korean", korean: "한국어", japanese: "韓国語", chineseSimplified: "韩语")
        case "ja-JP":
            localized(english: "Japanese", korean: "일본어", japanese: "日本語", chineseSimplified: "日语")
        case "zh-CN":
            localized(english: "Chinese Simplified", korean: "중국어 간체", japanese: "簡体字中国語", chineseSimplified: "简体中文")
        case "es-ES":
            localized(english: "Spanish", korean: "스페인어", japanese: "スペイン語", chineseSimplified: "西班牙语")
        case "fr-FR":
            localized(english: "French", korean: "프랑스어", japanese: "フランス語", chineseSimplified: "法语")
        case "de-DE":
            localized(english: "German", korean: "독일어", japanese: "ドイツ語", chineseSimplified: "德语")
        default:
            fallback
        }
    }
}
