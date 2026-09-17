import Foundation

struct LocalTranslationConfiguration: Equatable, Sendable {
    static let defaultBaseURLString = "http://127.0.0.1:8080/v1"
    static let defaultModelID = "mlx-community/Hy-MT2-7B-8bit"
    static let legacyDefaultModelIDs = Set([
        "mlx-community/Hunyuan-MT-7B-4bit"
    ])

    let baseURLString: String
    let modelID: String

    var trimmedBaseURLString: String {
        baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedModelID: String {
        let value = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        // Repository IDs remain unchanged. Explicit filesystem paths must use
        // the same canonical ID in setup, mlx_lm.server, /models, and requests.
        guard value.hasPrefix("/") || value.hasPrefix("~/")
                || value.hasPrefix("./") || value.hasPrefix("../")
        else { return value }
        let path = (value as NSString).expandingTildeInPath
        return URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }

    static func migratedModelID(_ modelID: String) -> String {
        let trimmedModelID = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        return legacyDefaultModelIDs.contains(trimmedModelID) ? defaultModelID : trimmedModelID
    }
}

enum LocalTranslationConnectionState: Equatable, Sendable {
    case unchecked
    case checking
    case available
    case unavailable(String)
}
