import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case chineseSimplified = "zh-Hans"
    case chineseTraditional = "zh-Hant"
    case japanese = "ja"
    case korean = "ko"
    case french = "fr"
    case german = "de"
    case spanish = "es"
    case portuguese = "pt"
    case russian = "ru"
    case arabic = "ar"
    case hindi = "hi"
    case italian = "it"
    case turkish = "tr"
    case vietnamese = "vi"
    case kazakh = "kk"
    case kyrgyz = "ky"

    static let storageKey = "app_language"
    static let autoStorageValue = "auto"
    static let defaultLanguage: AppLanguage = .english

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english:
            return "English"
        case .chineseSimplified:
            return "中文（简体）"
        case .chineseTraditional:
            return "中文（繁體）"
        case .japanese:
            return "日本語"
        case .korean:
            return "한국어"
        case .french:
            return "Français"
        case .german:
            return "Deutsch"
        case .spanish:
            return "Español"
        case .portuguese:
            return "Português"
        case .russian:
            return "Русский"
        case .arabic:
            return "العربية"
        case .hindi:
            return "हिन्दी"
        case .italian:
            return "Italiano"
        case .turkish:
            return "Türkçe"
        case .vietnamese:
            return "Tiếng Việt"
        case .kazakh:
            return "Қазақша"
        case .kyrgyz:
            return "Кыргызча"
        }
    }

    var promptDisplayName: String {
        switch self {
        case .english:
            return "英语"
        case .chineseSimplified:
            return "简体中文"
        case .chineseTraditional:
            return "繁体中文"
        case .japanese:
            return "日语"
        case .korean:
            return "韩语"
        case .french:
            return "法语"
        case .german:
            return "德语"
        case .spanish:
            return "西班牙语"
        case .portuguese:
            return "葡萄牙语"
        case .russian:
            return "俄语"
        case .arabic:
            return "阿拉伯语"
        case .hindi:
            return "印地语"
        case .italian:
            return "意大利语"
        case .turkish:
            return "土耳其语"
        case .vietnamese:
            return "越南语"
        case .kazakh:
            return "哈萨克语"
        case .kyrgyz:
            return "吉尔吉斯语"
        }
    }

    var localeIdentifier: String { rawValue }

    static func storedPreference(userDefaults: UserDefaults = .standard) -> AppLanguage? {
        let storedValue = userDefaults.string(forKey: storageKey) ?? autoStorageValue
        guard storedValue != autoStorageValue else { return nil }
        return AppLanguage(rawValue: storedValue)
    }

    static func storedLanguage(userDefaults: UserDefaults = .standard) -> AppLanguage {
        storedPreference(userDefaults: userDefaults) ?? resolvedSystemLanguage()
    }

    static func resolvedSystemLanguage(
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> AppLanguage {
        for identifier in preferredLanguages {
            if let matched = matchSystemLanguageIdentifier(identifier) {
                return matched
            }
        }
        return defaultLanguage
    }

    private static func matchSystemLanguageIdentifier(_ identifier: String) -> AppLanguage? {
        let normalized = identifier.lowercased()

        if normalized.hasPrefix("zh") {
            let traditionalMarkers = ["hant", "traditional", "tw", "hk", "mo"]
            if traditionalMarkers.contains(where: normalized.contains) {
                return .chineseTraditional
            }
            return .chineseSimplified
        }
        if normalized.hasPrefix("en") { return .english }
        if normalized.hasPrefix("ja") { return .japanese }
        if normalized.hasPrefix("ko") { return .korean }
        if normalized.hasPrefix("fr") { return .french }
        if normalized.hasPrefix("de") { return .german }
        if normalized.hasPrefix("es") { return .spanish }
        if normalized.hasPrefix("pt") { return .portuguese }
        if normalized.hasPrefix("ru") { return .russian }
        if normalized.hasPrefix("ar") { return .arabic }
        if normalized.hasPrefix("hi") { return .hindi }
        if normalized.hasPrefix("it") { return .italian }
        if normalized.hasPrefix("tr") { return .turkish }
        if normalized.hasPrefix("vi") { return .vietnamese }
        if normalized.hasPrefix("kk") { return .kazakh }
        if normalized.hasPrefix("ky") { return .kyrgyz }

        return nil
    }
}
