import SwiftUI

struct ContentView: View {
    @Bindable var session: TranslationSessionStore
    @State private var isFloatingCaptionVisible = FloatingCaptionWindowController.isOpen
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(session: session)
                .navigationSplitViewColumnWidth(min: 250, ideal: 270, max: 300)
        } detail: {
            CaptionBoardView(session: session)
        }
        .navigationTitle(AppText.appName)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: toggleCapture) {
                    Label(captureTitle, systemImage: capturePhase.actionSystemImage)
                }
                .buttonStyle(.borderedProminent)
                .labelStyle(.titleAndIcon)
                .tint(session.isRunning || session.isStarting ? .red : .accentColor)
                .disabled(capturePhase == .idle && !session.canStartTranslation)
                .accessibilityLabel(captureTitle)
                .accessibilityValue(session.statusMessage)

                if session.isRunning {
                    Button {
                        session.isPaused ? session.resume() : session.pause()
                    } label: {
                        Label(session.isPaused ? AppText.resume : AppText.pause,
                              systemImage: session.isPaused ? "play.fill" : "pause.fill")
                    }
                }

                Button {
                    FloatingCaptionWindowController.toggle(session: session)
                    syncFloatingCaptionVisibility()
                } label: {
                    Label(AppText.floatingCaptions,
                          systemImage: isFloatingCaptionVisible ? "captions.bubble.fill" : "captions.bubble")
                }
                .help(AppText.floatingCaptions)
                .accessibilityValue(isFloatingCaptionVisible ? AppText.floatingCaptionPowerOn : AppText.floatingCaptionPowerOff)

                SettingsLink { Label(AppText.settings, systemImage: "gearshape") }
            }
        }
        .onAppear { syncFloatingCaptionVisibility() }
        .onReceive(NotificationCenter.default.publisher(for: FloatingCaptionWindowController.visibilityDidChangeNotification)) { _ in
            syncFloatingCaptionVisibility()
        }
    }

    private var capturePhase: MenuBarCapturePhase {
        MenuBarCapturePhase(isRunning: session.isRunning, isStarting: session.isStarting, isPaused: session.isPaused)
    }

    private var captureTitle: String {
        capturePhase == .idle ? LocalUI.text("开始翻译", "Start translating") : capturePhase.actionTitle
    }

    private func toggleCapture() {
        if session.isRunning || session.isStarting {
            session.stop()
        } else {
            session.start()
            FloatingCaptionWindowController.open(session: session)
            syncFloatingCaptionVisibility()
        }
    }

    private func syncFloatingCaptionVisibility() {
        isFloatingCaptionVisible = FloatingCaptionWindowController.isOpen
    }
}
