import Foundation

enum ChatMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case chat
    case translation

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chat:
            return "聊天"
        case .translation:
            return "翻译"
        }
    }
}

enum TranslationLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case simplifiedChinese
    case traditionalChinese
    case english
    case japanese
    case korean
    case french
    case german
    case spanish
    case portuguese
    case russian
    case arabic
    case hindi
    case italian
    case turkish
    case vietnamese
    case uyghur
    case tibetan
    case mongolian
    case kazakh
    case kyrgyz

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .simplifiedChinese:
            return "中文(简体)"
        case .traditionalChinese:
            return "中文(繁体)"
        case .english:
            return "英语"
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
        case .uyghur:
            return "维吾尔语"
        case .tibetan:
            return "藏语"
        case .mongolian:
            return "蒙古语"
        case .kazakh:
            return "哈萨克语"
        case .kyrgyz:
            return "吉尔吉斯语"
        }
    }

    var llmTargetCode: String {
        switch self {
        case .simplifiedChinese:
            return "zh-CN"
        case .traditionalChinese:
            return "zh-TW"
        case .english:
            return "en"
        case .japanese:
            return "ja"
        case .korean:
            return "ko"
        case .french:
            return "fr"
        case .german:
            return "de"
        case .spanish:
            return "es"
        case .portuguese:
            return "pt"
        case .russian:
            return "ru"
        case .arabic:
            return "ar"
        case .hindi:
            return "hi"
        case .italian:
            return "it"
        case .turkish:
            return "tr"
        case .vietnamese:
            return "vi"
        case .uyghur:
            return "ug"
        case .tibetan:
            return "bo"
        case .mongolian:
            return "mn"
        case .kazakh:
            return "kk"
        case .kyrgyz:
            return "ky"
        }
    }
}

struct TranslationSettings: Codable, Equatable, Sendable {
    var sourceLanguage: TranslationLanguage
    var targetLanguage: TranslationLanguage

    static let `default` = TranslationSettings(sourceLanguage: .english, targetLanguage: .simplifiedChinese)

    var isIdentity: Bool {
        sourceLanguage == targetLanguage
    }

    mutating func swap() {
        let oldSource = sourceLanguage
        sourceLanguage = targetLanguage
        targetLanguage = oldSource
    }
}
