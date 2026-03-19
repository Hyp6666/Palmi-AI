import Foundation

nonisolated enum ReasoningMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case thinking
    case noThinking

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .thinking:
            return "brain.head.profile.fill"
        case .noThinking:
            return "text.word.spacing"
        }
    }

    var isThinkingEnabled: Bool {
        self == .thinking
    }

    mutating func toggle() {
        self = self == .thinking ? .noThinking : .thinking
    }
}
