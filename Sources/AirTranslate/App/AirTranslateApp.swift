import AppKit
import SwiftUI

@main
struct AirTranslateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var session = TranslationSessionStore()
    @State private var menuBarPanelController = MenuBarPanelController()

    var body: some Scene {
        WindowGroup("AirTranslate Local", id: AirTranslateWindowID.main) {
            ContentView(session: session)
                .frame(minWidth: 900, minHeight: 560)
                .background(MenuBarPanelInstaller(session: session, controller: menuBarPanelController))
                .onAppear { appDelegate.configure(session: session) }
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            CaptureCommands(session: session)
        }

        Settings {
            SettingsView(session: session)
        }
    }
}

@MainActor
private struct CaptureCommands: Commands {
    @Bindable var session: TranslationSessionStore

    var body: some Commands {
        CommandMenu(AppText.capture) {
            Button(session.isRunning || session.isStarting ? AppText.stop : AppText.start) {
                if session.isRunning || session.isStarting {
                    session.stop()
                } else {
                    session.start()
                    FloatingCaptionWindowController.open(session: session)
                }
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(!session.isRunning && !session.isStarting && !session.canStartTranslation)

            Button(session.isPaused ? AppText.resume : AppText.pause) {
                session.isPaused ? session.resume() : session.pause()
            }
            .keyboardShortcut(.space, modifiers: [.command, .shift])
            .disabled(!session.isRunning)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var session: TranslationSessionStore?

    func configure(session: TranslationSessionStore) {
        // Bind the installed SwiftUI state after the view appears, rather than
        // reading @State during App.init and starting a different store.
        guard self.session !== session else { return }
        self.session = session
        session.prepareLocalModel()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let appIcon = NSImage(named: "AppIcon") {
            NSApp.applicationIconImage = appIcon
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        session?.prepareForTermination()
    }
}
