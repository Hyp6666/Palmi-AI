import Foundation

extension AppAppearanceMode {
    var titleKey: AppLocalizedKey {
        switch self {
        case .light:
            return .appearanceLight
        case .dark:
            return .appearanceDark
        case .system:
            return .appearanceSystem
        }
    }
}

extension ChatTitleMode {
    var titleKey: AppLocalizedKey {
        switch self {
        case .content:
            return .chatTitleModeContent
        case .aiGenerated:
            return .chatTitleModeAI
        }
    }
}

extension ChatStyle {
    var titleKey: AppLocalizedKey {
        switch self {
        case .defaultStyle:
            return .chatStyleDefault
        case .efficiency:
            return .chatStyleEfficiency
        case .enthusiasm:
            return .chatStyleEnthusiasm
        case .gentle:
            return .chatStyleGentle
        case .serious:
            return .chatStyleSerious
        }
    }
}

extension ReasoningMode {
    var titleKey: AppLocalizedKey {
        switch self {
        case .thinking:
            return .reasoningThinking
        case .noThinking:
            return .reasoningDirect
        }
    }
}

extension ContextLength {
    var descriptionKey: AppLocalizedKey? {
        switch self {
        case .standard:
            return .contextLengthShort
        case .enhanced:
            return .contextLengthMedium
        case .maximum:
            return .contextLengthLong
        case .custom:
            return nil
        }
    }
}

extension EngineModuleStatus {
    var titleKey: AppLocalizedKey {
        switch self {
        case .notLoaded:
            return .moduleStatusWaiting
        case .loading:
            return .moduleStatusLoading
        case .loaded:
            return .moduleStatusReady
        case .failed:
            return .moduleStatusError
        }
    }
}
