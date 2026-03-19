import Foundation

enum ChatTitleMode: String, CaseIterable, Identifiable {
    case content
    case aiGenerated

    static let storageKey = "chat_title_mode"

    var id: String { rawValue }
}
