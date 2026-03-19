import Foundation

enum MessageRole: String, Codable, Sendable, Equatable {
    case user
    case assistant
}

struct Message: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let role: MessageRole
    var content: String
    var thinking: String?
    var imageAttachments: [Data]
    let timestamp: Date

    var imageData: Data? {
        imageAttachments.first
    }

    init(
        role: MessageRole,
        content: String,
        thinking: String? = nil,
        imageData: Data? = nil,
        imageAttachments: [Data] = []
    ) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.thinking = thinking
        self.imageAttachments = Self.normalizedAttachments(imageData: imageData, imageAttachments: imageAttachments)
        self.timestamp = Date()
    }

    init(
        id: UUID,
        role: MessageRole,
        content: String,
        thinking: String? = nil,
        imageData: Data? = nil,
        imageAttachments: [Data] = [],
        timestamp: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.thinking = thinking
        self.imageAttachments = Self.normalizedAttachments(imageData: imageData, imageAttachments: imageAttachments)
        self.timestamp = timestamp
    }

    enum CodingKeys: String, CodingKey {
        case id
        case role
        case content
        case thinking
        case imageData
        case imageAttachments
        case timestamp
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        role = try container.decode(MessageRole.self, forKey: .role)
        content = try container.decode(String.self, forKey: .content)
        thinking = try container.decodeIfPresent(String.self, forKey: .thinking)
        timestamp = try container.decode(Date.self, forKey: .timestamp)

        if let attachments = try container.decodeIfPresent([Data].self, forKey: .imageAttachments) {
            imageAttachments = attachments
        } else if let legacyImage = try container.decodeIfPresent(Data.self, forKey: .imageData) {
            imageAttachments = [legacyImage]
        } else {
            imageAttachments = []
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(role, forKey: .role)
        try container.encode(content, forKey: .content)
        try container.encodeIfPresent(thinking, forKey: .thinking)
        try container.encode(imageAttachments, forKey: .imageAttachments)
        try container.encode(timestamp, forKey: .timestamp)
    }

    private static func normalizedAttachments(imageData: Data?, imageAttachments: [Data]) -> [Data] {
        let filtered = imageAttachments.filter { !$0.isEmpty }
        if !filtered.isEmpty {
            return filtered
        }
        if let imageData, !imageData.isEmpty {
            return [imageData]
        }
        return []
    }
}
