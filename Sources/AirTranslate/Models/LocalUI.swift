import Foundation

enum LocalUI {
    static func text(_ chinese: String, _ english: String) -> String {
        AppText.localized(english: english, korean: english, japanese: english, chineseSimplified: chinese)
    }
}
