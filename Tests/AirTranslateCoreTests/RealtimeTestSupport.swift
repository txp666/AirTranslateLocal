import Foundation

final class StandardUserDefaultsTestLock: @unchecked Sendable {
    static let shared = StandardUserDefaultsTestLock()

    private let lock = NSRecursiveLock()

    private init() {}

    func withLock<Result>(_ body: () throws -> Result) rethrows -> Result {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}
