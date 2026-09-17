import Foundation

enum StartReadinessIssue: Equatable {
    case localAssetsChecking
    case localAssetsDownloadRequired
    case localAssetsUnavailable(String)
}

struct StartReadinessAssessment: Equatable {
    let issue: StartReadinessIssue?

    var canStart: Bool {
        issue == nil
    }
}

enum StartReadinessPolicy {
    static func assess(
        requiredLocalModelAvailability: ModelAvailability?
    ) -> StartReadinessAssessment {
        guard let requiredLocalModelAvailability else {
            return StartReadinessAssessment(issue: nil)
        }

        switch requiredLocalModelAvailability.state {
        case .installed:
            return StartReadinessAssessment(issue: nil)
        case .checking, .downloading:
            return StartReadinessAssessment(issue: .localAssetsChecking)
        case .downloadRequired:
            return StartReadinessAssessment(issue: .localAssetsDownloadRequired)
        case .unsupported, .unavailable, .failed:
            return StartReadinessAssessment(issue: .localAssetsUnavailable(requiredLocalModelAvailability.detail))
        }
    }
}
