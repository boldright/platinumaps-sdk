import Foundation

/// Languages supported by the Platinumaps web app. The raw value matches the
/// `culture` query parameter the web app expects.
enum PMLocale: String, Sendable {
    /// Japanese.
    case ja = "ja"

    /// English.
    case en = "en"

    /// Simplified Chinese.
    case zhHans = "zh-cn"

    /// Traditional Chinese.
    case zhHant = "zh-tw"

    /// Korean.
    case ko = "ko"

    /// French.
    case fr = "fr"

    /// Spanish.
    case es = "es"

    /// Vietnamese.
    case vi = "vi"

    /// Indonesian.
    case id = "id"

    /// Burmese.
    case my = "my"

    /// Thai.
    case th = "th"
}
