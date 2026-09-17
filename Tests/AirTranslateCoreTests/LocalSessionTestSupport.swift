import Foundation
@testable import AirTranslate

/// Prevent presentation tests from changing the installed app's settings.
final class InMemoryUserDefaults: UserDefaults, @unchecked Sendable {
    private let storageLock = NSLock()
    private var values: [String: Any] = [:]

    override func object(forKey defaultName: String) -> Any? {
        storageLock.lock()
        defer { storageLock.unlock() }
        return values[defaultName]
    }

    override func set(_ value: Any?, forKey defaultName: String) {
        storageLock.lock()
        values[defaultName] = value
        storageLock.unlock()
    }

    override func set(_ value: Bool, forKey defaultName: String) {
        set(value as Any, forKey: defaultName)
    }

    override func string(forKey defaultName: String) -> String? { object(forKey: defaultName) as? String }
    override func bool(forKey defaultName: String) -> Bool { object(forKey: defaultName) as? Bool ?? false }
    override func removeObject(forKey defaultName: String) { set(nil, forKey: defaultName) }
}

@MainActor
func makeLocalTestSession(preferences: UserDefaults = InMemoryUserDefaults()) -> TranslationSessionStore {
    TranslationSessionStore(
        preferences: preferences,
        speechAvailabilityProvider: { _ in ModelAvailability(state: .installed, detail: "Installed") },
        translationProvider: { _, _, _, _ in throw CancellationError() }
    )
}
