import Foundation
import Testing
@testable import AirTranslate

private enum ReservedAssetStatus: Sendable { case installed, supported }

private actor AvailabilityReservationInventory {
    private(set) var isReserved = false
    private(set) var reserveCount = 0
    private(set) var releaseCount = 0
    private var statusContinuation: CheckedContinuation<ReservedAssetStatus, Never>?

    func reserve(_ locale: Locale) -> Bool {
        reserveCount += 1
        let changed = !isReserved
        isReserved = true
        return changed
    }

    func release(_ locale: Locale) -> Bool {
        releaseCount += 1
        isReserved = false
        return true
    }

    func status(assetsInstalled: Bool) -> ReservedAssetStatus {
        isReserved && assetsInstalled ? .installed : .supported
    }

    func suspendedStatus() async -> ReservedAssetStatus {
        await withCheckedContinuation { statusContinuation = $0 }
    }

    var isStatusPending: Bool { statusContinuation != nil }

    func finishStatus() {
        statusContinuation?.resume(returning: .installed)
        statusContinuation = nil
    }
}

@Suite
struct ModelAvailabilityReservationTests {
    @Test(arguments: [true, false])
    func checkingUsesReservationToDistinguishCachedAssetsFromRealDownloadNeed(assetsInstalled: Bool) async throws {
        let inventory = AvailabilityReservationInventory()
        let coordinator = SpeechAssetReservationCoordinator(
            reserveLocale: { await inventory.reserve($0) },
            releaseLocale: { await inventory.release($0) }
        )
        #expect(await inventory.status(assetsInstalled: assetsInstalled) == .supported)
        let actual = try await ModelAvailabilityChecker.withSpeechAssetReservation(
            locale: Locale(identifier: "ja_JP"), coordinator: coordinator
        ) {
            await inventory.status(assetsInstalled: assetsInstalled)
        }
        #expect(actual == (assetsInstalled ? .installed : .supported))
        #expect(await inventory.reserveCount == 1)
        #expect(await inventory.releaseCount == 1)
        #expect(!(await inventory.isReserved))
    }

    @Test
    func cancellingAvailabilityCheckDoesNotReleaseNewCapturingOwner() async throws {
        let inventory = AvailabilityReservationInventory()
        let coordinator = SpeechAssetReservationCoordinator(
            reserveLocale: { await inventory.reserve($0) },
            releaseLocale: { await inventory.release($0) }
        )
        let locale = Locale(identifier: "ja_JP")
        let oldCheck = Task {
            _ = try await ModelAvailabilityChecker.withSpeechAssetReservation(locale: locale, coordinator: coordinator) {
                await inventory.suspendedStatus()
            }
        }
        let deadline = Date().addingTimeInterval(2)
        while !(await inventory.isStatusPending), Date() < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        try #require(await inventory.isStatusPending)
        oldCheck.cancel()
        let capture = try await coordinator.reserve(locale: locale) { _ in true }
        await inventory.finishStatus()
        do {
            _ = try await oldCheck.value
            Issue.record("Cancelled availability query unexpectedly succeeded")
        } catch {
            #expect(error is CancellationError)
        }
        #expect(await inventory.reserveCount == 1)
        #expect(await inventory.releaseCount == 0)
        #expect(await inventory.isReserved)
        await coordinator.release(capture)
        #expect(await inventory.releaseCount == 1)
        #expect(!(await inventory.isReserved))
    }
}
