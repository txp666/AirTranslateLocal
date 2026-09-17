import Foundation
import Speech

enum ModelAvailabilityChecker {
    static func speechAvailability(for language: LanguageOption) async -> ModelAvailability {
        guard SpeechTranscriber.isAvailable else {
            return ModelAvailability(
                state: .unavailable,
                detail: AppText.speechModelAvailabilityDetail(
                    source: language.localizedTitle,
                    status: ModelAvailabilityState.unavailable.title
                )
            )
        }

        guard let supportedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: language.locale) else {
            return ModelAvailability(
                state: .unsupported,
                detail: AppText.speechModelAvailabilityDetail(
                    source: language.localizedTitle,
                    status: ModelAvailabilityState.unsupported.title
                )
            )
        }

        let transcriber = SpeechTranscriber(locale: supportedLocale, preset: .progressiveTranscription)
        do {
            // AssetInventory.status is scoped to the app's locale reservation.
            // Cached assets can report .supported after the previous analyzer
            // releases its locale. Query with the same lease used by capture;
            // this does not start an installation or download.
            let status = try await withSpeechAssetReservation(locale: supportedLocale) {
                await AssetInventory.status(forModules: [transcriber])
            }
            let state = availabilityState(for: status)
            return ModelAvailability(
                state: state,
                detail: AppText.speechModelAvailabilityDetail(
                    source: language.localizedTitle,
                    status: state.title
                )
            )
        } catch is CancellationError {
            return .checking
        } catch {
            return ModelAvailability(state: .failed, detail: error.localizedDescription)
        }
    }

    static func downloadSpeechAssets(for language: LanguageOption) async throws {
        guard let supportedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: language.locale) else {
            return
        }

        let transcriber = SpeechTranscriber(locale: supportedLocale, preset: .progressiveTranscription)
        try await withSpeechAssetReservation(locale: supportedLocale) {
            guard let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) else {
                return
            }
            try await request.downloadAndInstall()
        }
    }

    /// Share capture's reference-counted lease so a concurrent availability
    /// check, cancelled check, or download cannot release another owner.
    static func withSpeechAssetReservation<Result>(
        locale: Locale,
        coordinator: SpeechAssetReservationCoordinator = .shared,
        operation: () async throws -> Result
    ) async throws -> Result {
        let reservation = try await coordinator.reserve(locale: locale) { _ in !Task.isCancelled }
        do {
            let result = try await operation()
            try Task.checkCancellation()
            await coordinator.release(reservation)
            return result
        } catch {
            await coordinator.release(reservation)
            throw error
        }
    }

    private static func availabilityState(
        for status: AssetInventory.Status
    ) -> ModelAvailabilityState {
        switch status {
        case .installed:
            .installed
        case .downloading:
            .downloading
        case .supported:
            .downloadRequired
        case .unsupported:
            .unsupported
        @unknown default:
            .failed
        }
    }

}
