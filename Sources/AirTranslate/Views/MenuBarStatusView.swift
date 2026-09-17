import SwiftUI

struct MenuBarStatusView: View {
    @Bindable var session: TranslationSessionStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @State private var isFloatingCaptionVisible = FloatingCaptionWindowController.isOpen

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AppText.appName).font(.headline)
            Text(session.languageSummary).font(.subheadline)
            Text(session.statusMessage).font(.caption).foregroundStyle(.secondary)
            Divider()
            Button {
                if session.isRunning || session.isStarting {
                    session.stop()
                } else {
                    session.start()
                    FloatingCaptionWindowController.open(session: session)
                }
            } label: {
                Label(phase.actionTitle, systemImage: phase.actionSystemImage)
            }
            .disabled(phase == .idle && !session.canStartTranslation)
            if session.isRunning {
                Button(session.isPaused ? AppText.resume : AppText.pause,
                       systemImage: session.isPaused ? "play.fill" : "pause.fill") {
                    session.isPaused ? session.resume() : session.pause()
                }
            }
            Button(isFloatingCaptionVisible ? AppText.hideFloatingCaptions : AppText.showFloatingCaptions,
                   systemImage: "captions.bubble") {
                FloatingCaptionWindowController.toggle(session: session)
            }
            Divider()
            Button(LocalUI.text("打开主窗口", "Open main window"), systemImage: "macwindow") {
                openWindow(id: AirTranslateWindowID.main)
                NSApp.activate(ignoringOtherApps: true)
            }
            Button(AppText.settings, systemImage: "gearshape") { openSettings() }
            Button(AppText.quit, systemImage: "power") { NSApp.terminate(nil) }
        }
        .buttonStyle(.plain)
        .padding(16)
        .frame(width: 280, alignment: .leading)
        .onAppear { isFloatingCaptionVisible = FloatingCaptionWindowController.isOpen }
        .onReceive(NotificationCenter.default.publisher(for: FloatingCaptionWindowController.visibilityDidChangeNotification)) { _ in
            isFloatingCaptionVisible = FloatingCaptionWindowController.isOpen
        }
    }

    private var phase: MenuBarCapturePhase {
        MenuBarCapturePhase(isRunning: session.isRunning, isStarting: session.isStarting, isPaused: session.isPaused)
    }
}

enum MenuBarCapturePhase: Equatable {
    case idle
    case starting
    case running
    case paused

    init(isRunning: Bool, isStarting: Bool, isPaused: Bool) {
        if isStarting {
            self = .starting
        } else if isRunning {
            self = isPaused ? .paused : .running
        } else {
            self = .idle
        }
    }

    var actionSystemImage: String {
        switch self {
        case .idle:
            "play.fill"
        case .starting:
            "xmark"
        case .running, .paused:
            "stop.fill"
        }
    }

    var actionTitle: String {
        switch self {
        case .idle:
            AppText.start
        case .starting:
            AppText.cancel
        case .running, .paused:
            AppText.stop
        }
    }

    func actionSubtitle(statusMessage: String) -> String {
        switch self {
        case .idle:
            AppText.ready
        case .starting:
            statusMessage
        case .running:
            AppText.menuBarRunningTitle
        case .paused:
            AppText.paused
        }
    }
}
