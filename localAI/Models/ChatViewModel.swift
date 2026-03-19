import SwiftUI
import Combine
import OSLog

extension Notification.Name {
    static let localAIHistoryReset = Notification.Name("localAI.historyReset")
    static let localAIDefaultSettingsReset = Notification.Name("localAI.defaultSettingsReset")
}

enum ContextLength: Identifiable, Equatable, Hashable {
    case standard
    case enhanced
    case maximum
    case custom(Int)

    static let presets: [ContextLength] = [.standard, .enhanced, .maximum]

    static let customMin = 100
    static let customMax = 262_143

    var id: String {
        switch self {
        case .standard: return "4K"
        case .enhanced: return "16K"
        case .maximum: return "32K"
        case .custom(let count): return "custom_\(count)"
        }
    }

    var tokenCount: Int {
        switch self {
        case .standard: return 4096
        case .enhanced: return 16384
        case .maximum: return 32768
        case .custom(let count): return count
        }
    }

    var displayLabel: String {
        switch self {
        case .standard: return "4K"
        case .enhanced: return "16K"
        case .maximum: return "32K"
        case .custom(let count): return "\(count)"
        }
    }

    var isPreset: Bool {
        switch self {
        case .standard, .enhanced, .maximum: return true
        case .custom: return false
        }
    }
}

extension ContextLength: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case value
    }

    init(from decoder: Decoder) throws {
        // Support decoding legacy raw string format ("4K", "16K", "32K")
        if let container = try? decoder.singleValueContainer(),
           let rawValue = try? container.decode(String.self) {
            switch rawValue {
            case "4K": self = .standard
            case "16K": self = .enhanced
            case "32K": self = .maximum
            default: self = .enhanced
            }
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "standard": self = .standard
        case "enhanced": self = .enhanced
        case "maximum": self = .maximum
        case "custom":
            let value = try container.decode(Int.self, forKey: .value)
            self = .custom(value.clamped(to: Self.customMin...Self.customMax))
        default: self = .enhanced
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .standard:
            try container.encode("standard", forKey: .type)
        case .enhanced:
            try container.encode("enhanced", forKey: .type)
        case .maximum:
            try container.encode("maximum", forKey: .type)
        case .custom(let value):
            try container.encode("custom", forKey: .type)
            try container.encode(value, forKey: .value)
        }
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

enum EngineModuleStatus: Equatable {
    case notLoaded
    case loading
    case loaded
    case failed(String)
}

enum ConversationPhase: String, Equatable {
    case idle
    case generating
    case stopping
    case switchingMode
    case restoring
}

struct ConversationHistoryItem: Identifiable, Equatable {
    let id: UUID
    let title: String
    let updatedAt: Date
    let messageCount: Int
    let mode: ChatMode
}

private struct ConversationRecord: Identifiable, Codable {
    let id: UUID
    let createdAt: Date
    var updatedAt: Date
    var mode: ChatMode
    var translationSettings: TranslationSettings?
    var contextLength: ContextLength
    var messages: [Message]
    var overrideTitle: String?
    var aiTitle: String?
    var legacyTitle: String?

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case updatedAt
        case mode
        case translationSettings
        case contextLength
        case messages
        case overrideTitle
        case aiTitle
        case legacyTitle = "title"
    }
}

private struct ConversationStore: Codable {
    let version: Int
    let savedAt: Date
    let activeConversationID: UUID?
    let activeMode: ChatMode?
    let activeTranslationSettings: TranslationSettings?
    let conversations: [ConversationRecord]
}

private struct LegacyConversationSnapshot: Codable {
    let version: Int
    let savedAt: Date
    let contextLength: ContextLength
    let messages: [Message]
}

private enum ConversationTitleGenerator {
    static let titleContextLength: Int32 = 16384

    static func firstUserMessage(in messages: [Message]) -> String {
        messages.first(where: { $0.role == .user && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?.content
        ?? messages.first(where: { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?.content
        ?? ""
    }

    static func promptMessages(for firstUserMessage: String, language: AppLanguage) -> [PromptMessage] {
        return [
            PromptMessage(role: .system, content: systemPrompt(for: language)),
            PromptMessage(role: .user, content: firstUserMessage)
        ]
    }

    private static func systemPrompt(for language: AppLanguage) -> String {
        switch language {
        case .english:
            return "You are a language summarization expert. When a user sends a message, reply in English and summarize the message into a concise title of no more than 15 words. No matter what the user sends, you only need to summarize the content and output the title directly, without any explanation or extra text."
        case .chineseSimplified:
            return "你是一个语言概括专家。对于用户发来的话，你需要用中文回复，用简短的话把用户发来的内容概括为一个标题，字数限制在15个字以内。无论用户发来什么内容，你都只需要概括其内容并直接输出标题，不要添加任何解释或其他内容。"
        case .chineseTraditional:
            return "你是一個語言概括專家。對於使用者發來的話，你需要用繁體中文回覆，用簡短的話把使用者發來的內容概括為一個標題，字數限制在15個字以內。無論使用者發來什麼內容，你都只需要概括其內容並直接輸出標題，不要添加任何解釋或其他內容。"
        case .japanese:
            return "あなたは言語要約の専門家です。ユーザーからメッセージが届いたら、日本語で返信し、その内容を15文字以内の簡潔なタイトルに要約してください。ユーザーが何を送ってきても、内容を要約したタイトルだけをそのまま出力し、説明や余計な文は加えないでください。"
        case .korean:
            return "당신은 문장 요약 전문가입니다. 사용자가 메시지를 보내면 한국어로 답하고, 그 내용을 15자 이내의 간결한 제목으로 요약하세요. 사용자가 무엇을 보내더라도 내용만 요약한 제목만 바로 출력하고, 설명이나 다른 문장은 추가하지 마세요."
        case .french:
            return "Vous êtes un expert en synthèse linguistique. Lorsque l'utilisateur envoie un message, répondez en français et résumez son contenu sous la forme d'un titre concis de 15 mots maximum. Quel que soit le message reçu, vous devez uniquement résumer le contenu et afficher directement le titre, sans explication ni texte supplémentaire."
        case .german:
            return "Du bist ein Experte für sprachliche Zusammenfassungen. Wenn der Benutzer dir eine Nachricht sendet, antworte auf Deutsch und fasse den Inhalt zu einem prägnanten Titel mit höchstens 15 Wörtern zusammen. Egal, was der Benutzer sendet, du sollst nur den Inhalt zusammenfassen und den Titel direkt ausgeben, ohne Erklärungen oder zusätzlichen Text."
        case .spanish:
            return "Eres un experto en síntesis del lenguaje. Cuando el usuario te envíe un mensaje, responde en español y resume su contenido en un título breve de no más de 15 palabras. Sin importar lo que envíe el usuario, solo debes resumir el contenido y mostrar directamente el título, sin explicaciones ni texto adicional."
        case .portuguese:
            return "Você é um especialista em síntese de linguagem. Quando o usuário enviar uma mensagem, responda em português e resuma o conteúdo em um título curto de no máximo 15 palavras. Independentemente do que o usuário enviar, você só deve resumir o conteúdo e mostrar diretamente o título, sem explicações nem texto adicional."
        case .russian:
            return "Вы специалист по языковому обобщению. Когда пользователь отправляет сообщение, отвечайте на русском языке и кратко резюмируйте его содержание в виде заголовка не длиннее 15 слов. Что бы ни прислал пользователь, вам нужно только обобщить содержание и сразу вывести заголовок без объяснений и дополнительного текста."
        case .arabic:
            return "أنت خبير في تلخيص اللغة. عندما يرسل المستخدم رسالة، رد بالعربية ولخّص محتواها في عنوان موجز لا يتجاوز 15 كلمة. مهما كان ما يرسله المستخدم، عليك فقط تلخيص المحتوى وإخراج العنوان مباشرة من دون أي شرح أو نص إضافي."
        case .hindi:
            return "आप भाषा-सार विशेषज्ञ हैं। जब उपयोगकर्ता कोई संदेश भेजे, तो हिंदी में उत्तर दें और उसकी सामग्री को 15 शब्दों से अधिक न होने वाले संक्षिप्त शीर्षक में सारांशित करें। उपयोगकर्ता कुछ भी भेजे, आपको केवल उसकी सामग्री का सार लेकर सीधे शीर्षक ही आउटपुट करना है, कोई व्याख्या या अतिरिक्त पाठ नहीं जोड़ना है।"
        case .italian:
            return "Sei un esperto di sintesi linguistica. Quando l'utente invia un messaggio, rispondi in italiano e riassumine il contenuto in un titolo conciso di non più di 15 parole. Qualunque cosa invii l'utente, devi solo riassumere il contenuto e mostrare direttamente il titolo, senza spiegazioni né testo aggiuntivo."
        case .turkish:
            return "Sen bir dil özetleme uzmanısın. Kullanıcı sana bir mesaj gönderdiğinde Türkçe yanıt ver ve içeriği en fazla 15 kelimelik kısa bir başlık halinde özetle. Kullanıcı ne gönderirse göndersin, yalnızca içeriği özetleyip başlığı doğrudan çıktı olarak ver; açıklama ya da ek metin yazma."
        case .vietnamese:
            return "Bạn là chuyên gia tóm tắt ngôn ngữ. Khi người dùng gửi tin nhắn, hãy trả lời bằng tiếng Việt và tóm tắt nội dung đó thành một tiêu đề ngắn gọn không quá 15 từ. Dù người dùng gửi nội dung gì, bạn chỉ cần tóm tắt nội dung và xuất trực tiếp tiêu đề, không thêm giải thích hay văn bản nào khác."
        case .kazakh:
            return "Сіз тілдік мазмұнды ықшамдап түйіндеу бойынша мамансыз. Пайдаланушы хабарлама жібергенде, қазақ тілінде жауап беріп, оның мазмұнын 15 сөзден аспайтын қысқа тақырыпқа жинақтаңыз. Пайдаланушы не жіберсе де, сіз тек мазмұнын жинақтап, тақырыпты бірден шығарыңыз, ешқандай түсіндірме немесе қосымша мәтін қоспаңыз."
        case .kyrgyz:
            return "Сиз тилдик жыйынтыктоо боюнча адиссиз. Колдонуучу билдирүү жөнөткөндө, кыргыз тилинде жооп берип, анын мазмунун 15 сөздөн ашпаган кыска аталышка жыйынтыктаңыз. Колдонуучу эмне жөнөтсө да, сиз мазмунун гана жыйынтыктап, аталышты түз эле чыгарыңыз; түшүндүрмө же кошумча текст кошпоңуз."
        }
    }

    static func cleanup(_ raw: String) -> String {
        let firstLine = raw
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? raw.trimmingCharacters(in: .whitespacesAndNewlines)

        let normalized = firstLine
            .replacingOccurrences(of: #"^<think>.*?</think>"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"^[“"'\s:：\-•·\[\(]+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[”"'\s:：\-•·\]\)]+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else { return "" }

        let words = normalized.split(whereSeparator: \.isWhitespace)
        if words.count > 1 {
            return words.prefix(10).joined(separator: " ")
        }

        return String(normalized.prefix(12))
    }
}

private actor StreamingTokenBuffer {
    private var bufferedText = ""

    func append(_ token: String) {
        guard !token.isEmpty else { return }
        bufferedText += token
    }

    func drain() -> String {
        let chunk = bufferedText
        bufferedText = ""
        return chunk
    }
}

private enum ChatAction: CustomStringConvertible {
    case send
    case stop
    case switchMode(ChatMode)
    case restoreConversation(UUID)
    case newConversation
    case changeContextLength(ContextLength)
    case toggleThinking(isStreaming: Bool)
    case persistence(PersistenceReason)

    var description: String {
        switch self {
        case .send:
            return "send"
        case .stop:
            return "stop"
        case .switchMode(let mode):
            return "switchMode:\(mode.rawValue)"
        case .restoreConversation(let id):
            return "restoreConversation:\(id.uuidString)"
        case .newConversation:
            return "newConversation"
        case .changeContextLength(let length):
            return "changeContextLength:\(length.displayLabel)"
        case .toggleThinking(let isStreaming):
            return isStreaming ? "toggleThinking:streaming" : "toggleThinking:stable"
        case .persistence(let reason):
            return "persist:\(reason.rawValue)"
        }
    }
}

private enum PersistenceReason: String {
    case send
    case completion
    case modeSwitch
    case restore
    case translationSettings
    case deleteConversation
    case renameConversation
    case titleGeneration
    case background
    case newConversation
    case contextLength
}

@MainActor
final class ChatViewModel: ObservableObject {
    private static let reasoningModePreferenceKey = "chat_reasoning_mode"
    private static let legacyThinkingPreferenceKey = "chat_thinking_enabled"
    private static let thinkingModeUnlockedKey = "thinking_mode_unlocked"
    private static let titleModePreferenceKey = ChatTitleMode.storageKey
    private static let chatStylePreferenceKey = ChatStyle.storageKey
    private static let streamingRefreshInterval: TimeInterval = 1.0 / 12.0
    private static let streamingTokenFlushInterval: TimeInterval = 1.0 / 14.0
    private static let thinkingToggleCooldown: TimeInterval = 0.25
    static let maxImageAttachmentCount = 3

    @Published private(set) var messages: [Message] = []
    @Published private(set) var isGenerating = false
    @Published private(set) var currentStreamingText = ""
    @Published private(set) var currentStreamingThinking = ""
    @Published private(set) var showsImageProcessingPlaceholder = false
    @Published private(set) var contextLength: ContextLength = .enhanced
    @Published private(set) var mode: ChatMode = .chat
    @Published private(set) var translationSettings: TranslationSettings = .default
    @Published private(set) var historyModeFilter: ChatMode = .chat
    @Published private(set) var reasoningMode: ReasoningMode
    @Published private(set) var moduleStatus: EngineModuleStatus = .notLoaded
    @Published private(set) var moduleLoadProgress: Double = 0
    @Published private(set) var historyItems: [ConversationHistoryItem] = []
    @Published private(set) var activeConversationID: UUID?
    @Published private(set) var titleMode: ChatTitleMode
    @Published private(set) var chatStyle: ChatStyle
    @Published private(set) var titleGeneratingConversationIDs: Set<UUID> = []
    @Published private(set) var sessionPhase: ConversationPhase = .idle
    @Published private(set) var isThinkingModeUnlocked: Bool
    @Published private(set) var debugStats = StabilityDebugStats()
    @Published private var chatDraft = ""
    @Published private var translationDraft = ""

    private let engine = LlamaMultimodalEngine()
    private let historyURL: URL
    private let persistenceQueue = DispatchQueue(label: "localAI.persistence", qos: .utility)
    private let diagnostics = StabilityDiagnostics()
    private var cancellables = Set<AnyCancellable>()

    private var storedConversations: [ConversationRecord] = []
    private var runningTask: Task<Void, Never>?
    private var transitionTask: Task<Void, Never>?
    private var pendingPersistenceWorkItem: DispatchWorkItem?
    private var pendingStreamingRefreshTask: Task<Void, Never>?
    private var titleGenerationTasks: [UUID: Task<Void, Never>] = [:]
    private var currentGenerationID: UUID?
    private var currentGenerationInterval: OSSignpostIntervalState?
    private var streamingRawText = ""
    private var activeGenerationReasoningMode: ReasoningMode?
    private var currentGenerationHasImages = false
    private var pendingStopDuringImageProcessing = false
    private var lastStreamingRefreshAt: TimeInterval = 0
    private var lastThinkingToggleAt: TimeInterval = 0
    private var expandedThinkingMessageIDs: Set<UUID> = []
    private var isStreamingThinkingExpanded = false
    private var backgroundInterruptedGeneration = false

    private static let thinkStartTags = ["<think>", "<thinking>", "<reasoning>", "<analysis>"]
    private static let thinkEndTags = ["</think>", "</thinking>", "</reasoning>", "</analysis>"]

    init() {
        let restoredReasoningMode: ReasoningMode
        let shouldPersistMigratedReasoning: Bool
        if let raw = UserDefaults.standard.string(forKey: Self.reasoningModePreferenceKey),
           let restored = ReasoningMode(rawValue: raw) {
            restoredReasoningMode = restored == .thinking ? .noThinking : restored
            shouldPersistMigratedReasoning = restored != .noThinking
        } else if UserDefaults.standard.object(forKey: Self.legacyThinkingPreferenceKey) != nil {
            restoredReasoningMode = .noThinking
            shouldPersistMigratedReasoning = true
        } else {
            restoredReasoningMode = .noThinking
            shouldPersistMigratedReasoning = true
        }

        reasoningMode = restoredReasoningMode
        isThinkingModeUnlocked = UserDefaults.standard.bool(forKey: Self.thinkingModeUnlockedKey)
        titleMode = ChatTitleMode(
            rawValue: UserDefaults.standard.string(forKey: Self.titleModePreferenceKey) ?? ""
        ) ?? .content
        chatStyle = ChatStyle(
            rawValue: UserDefaults.standard.string(forKey: Self.chatStylePreferenceKey) ?? ""
        ) ?? .defaultStyle
        historyURL = Self.makeHistoryURL()

        if shouldPersistMigratedReasoning {
            UserDefaults.standard.set(restoredReasoningMode.rawValue, forKey: Self.reasoningModePreferenceKey)
        }

        restoreConversationStore()
        enforceChatOnlyPresentation()
        if titleMode == .aiGenerated {
            prefetchMissingAITitlesIfNeeded()
        }
        observeExternalSettingsChanges()
    }

    var isInteractionLocked: Bool {
        transitionTask != nil || sessionPhase == .stopping || sessionPhase == .switchingMode || sessionPhase == .restoring
    }

    var shouldAutoScroll: Bool {
        !isInteractionLocked && Date().timeIntervalSinceReferenceDate - lastThinkingToggleAt >= Self.thinkingToggleCooldown
    }

    var canToggleThinkingDetails: Bool {
        !isInteractionLocked
    }

    func draft(for mode: ChatMode? = nil) -> String {
        switch mode ?? self.mode {
        case .chat:
            return chatDraft
        case .translation:
            return translationDraft
        }
    }

    func updateDraft(_ text: String, for mode: ChatMode? = nil) {
        setDraft(text, for: mode ?? self.mode)
    }

    func updateHistoryModeFilter(_ filter: ChatMode) {
        _ = filter
        let visibleFilter: ChatMode = .chat
        guard historyModeFilter != visibleFilter else { return }
        historyModeFilter = visibleFilter
        refreshHistoryItems()
    }

    func updateTranslationSourceLanguage(_ language: TranslationLanguage) {
        guard translationSettings.sourceLanguage != language else { return }
        translationSettings.sourceLanguage = language
        handleTranslationSettingsChanged()
    }

    func updateTranslationTargetLanguage(_ language: TranslationLanguage) {
        guard translationSettings.targetLanguage != language else { return }
        translationSettings.targetLanguage = language
        handleTranslationSettingsChanged()
    }

    func swapTranslationLanguages() {
        translationSettings.swap()
        handleTranslationSettingsChanged()
    }

    func updateTitleMode(rawValue: String) {
        let resolved = ChatTitleMode(rawValue: rawValue) ?? .content
        guard titleMode != resolved else { return }
        titleMode = resolved
        UserDefaults.standard.set(resolved.rawValue, forKey: Self.titleModePreferenceKey)
        refreshHistoryItems()
        if resolved == .aiGenerated {
            prefetchMissingAITitlesIfNeeded()
        }
    }

    func updateChatStyle(rawValue: String) {
        let resolved = ChatStyle(rawValue: rawValue) ?? .defaultStyle
        guard chatStyle != resolved else { return }
        chatStyle = resolved
        UserDefaults.standard.set(resolved.rawValue, forKey: Self.chatStylePreferenceKey)
    }

    func updateReasoningMode(_ mode: ReasoningMode) {
        guard reasoningMode != mode else { return }
        reasoningMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: Self.reasoningModePreferenceKey)
    }

    func refreshLocalizedHistoryItems() {
        refreshHistoryItems()
    }

    func setModuleLoadProgress(_ progress: Double) {
        let clamped = min(max(progress, 0), 1)
        guard abs(moduleLoadProgress - clamped) >= 0.005 || clamped == 0 || clamped == 1 else { return }
        moduleLoadProgress = clamped
    }

    func handleModuleLoadProgress(_ progress: Double) {
        setModuleLoadProgress(progress)
        guard progress >= 1 else { return }
        switch moduleStatus {
        case .loading, .loaded:
            moduleStatus = .loaded
        case .notLoaded, .failed:
            break
        }
    }

    func toggleReasoningMode() {
        updateReasoningMode(reasoningMode == .thinking ? .noThinking : .thinking)
    }

    func setThinkingModeUnlocked(_ unlocked: Bool) {
        guard isThinkingModeUnlocked != unlocked else { return }
        isThinkingModeUnlocked = unlocked
        UserDefaults.standard.set(unlocked, forKey: Self.thinkingModeUnlockedKey)
        if !unlocked {
            updateReasoningMode(.noThinking)
        }
    }

    func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .background:
            // When going to background during generation, iOS will invalidate
            // Metal/GPU resources while suspended. If the generation loop resumes
            // after that, llama_sampler_sample accesses invalid context → SIGABRT.
            // We must cancel the generation immediately and reset the engine.
            if isGenerating {
                runningTask?.cancel()
                runningTask = nil
                // Flush any partial output to messages so nothing is lost.
                flushStreamingPreview(force: true)
                let wasThinking = activeGenerationReasoningMode?.isThinkingEnabled == true
                savePartialGenerationOutput(wasThinking: wasThinking)
                backgroundInterruptedGeneration = true
            }
            persistStore(reason: .background)
        case .active:
            // After returning from background, clean up interrupted generation.
            if backgroundInterruptedGeneration {
                backgroundInterruptedGeneration = false
                finishInterruptedGeneration()
            }
        default:
            break
        }
    }

    /// Finalize state after a generation was interrupted by going to background.
    private func finishInterruptedGeneration() {
        currentGenerationID = nil
        activeGenerationReasoningMode = nil
        if let interval = currentGenerationInterval {
            diagnostics.endInterval("Generation", interval)
            currentGenerationInterval = nil
        }
        isGenerating = false
        resetStreamingState()
        sessionPhase = .idle
        // Reset the engine asynchronously to free stale C pointers.
        Task { [weak self] in
            guard let self else { return }
            await self.engine.reset()
            await MainActor.run {
                self.moduleStatus = .notLoaded
                self.moduleLoadProgress = 0
            }
        }
    }

    @discardableResult
    func send(_ text: String, imageDataList: [Data]) -> Bool {
        recordAction(.send)

        guard transitionTask == nil else {
            recordBlockedAction("send while \(sessionPhase.rawValue)")
            return false
        }
        guard !isGenerating else {
            recordBlockedAction("send while generating")
            return false
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedImageDataList = mode == .chat
            ? Array(imageDataList.filter { !$0.isEmpty }.prefix(Self.maxImageAttachmentCount))
            : []
        guard !trimmed.isEmpty || !normalizedImageDataList.isEmpty else { return false }

        setDraft("", for: mode)
        beginGeneration(userText: trimmed, imageDataList: normalizedImageDataList)
        return true
    }

    func stop() {
        recordAction(.stop)
        guard transitionTask == nil else {
            recordBlockedAction("stop while transition active")
            return
        }
        if currentGenerationHasImages && showsImageProcessingPlaceholder {
            pendingStopDuringImageProcessing = true
            return
        }
        queueTransition(phase: .stopping, action: .stop) {
            await self.stopGeneration(resetEngine: false, savePartial: true)
        }
    }

    func switchMode(to newMode: ChatMode) {
        guard newMode == .chat else {
            recordBlockedAction("translation mode hidden")
            return
        }
        recordAction(.switchMode(newMode))
        guard mode != newMode else { return }
        if isGenerating {
            debugStats.modeSwitchWhileGeneratingCount += 1
        }
        queueTransition(phase: .switchingMode, action: .switchMode(newMode)) {
            await self.stopGeneration(resetEngine: false)
            self.restoreMode(newMode)
            self.persistStore(reason: .modeSwitch)
        }
    }

    func loadConversation(id: UUID) {
        recordAction(.restoreConversation(id))
        queueTransition(phase: .restoring, action: .restoreConversation(id)) {
            await self.stopGeneration(resetEngine: false)
            guard let record = self.storedConversations.first(where: { $0.id == id }),
                  record.mode == .chat else { return }
            self.applyConversationRecord(record)
            self.persistStore(reason: .restore)
        }
    }

    func startNewConversation() {
        recordAction(.newConversation)
        queueTransition(phase: .restoring, action: .newConversation) {
            await self.stopGeneration(resetEngine: false)
            self.messages.removeAll()
            self.activeConversationID = nil
            self.currentStreamingText = ""
            self.currentStreamingThinking = ""
            self.restoreThinkingDefaults()
            self.persistStore(reason: .newConversation)
        }
    }

    func changeContextLength(to length: ContextLength) {
        recordAction(.changeContextLength(length))
        guard length != contextLength else { return }
        queueTransition(phase: .restoring, action: .changeContextLength(length)) {
            await self.stopGeneration(resetEngine: true)
            self.contextLength = length
            self.messages.removeAll()
            self.activeConversationID = nil
            self.moduleStatus = .notLoaded
            self.moduleLoadProgress = 0
            self.persistStore(reason: .contextLength)
        }
    }

    func preloadEngine() {
        guard !isGenerating, transitionTask == nil else { return }
        guard moduleStatus != .loading, moduleStatus != .loaded else { return }

        moduleStatus = .loading
        moduleLoadProgress = 0
        Task { [weak self] in
            guard let self else { return }
            let interval = diagnostics.beginInterval("EngineWarmup")
            do {
                try await engine.warmup(
                    contextLength: Int32(contextLength.tokenCount),
                    onLoadProgress: { progress in
                        await MainActor.run {
                            self.handleModuleLoadProgress(progress)
                        }
                    }
                )
                await MainActor.run {
                    self.diagnostics.endInterval("EngineWarmup", interval)
                    self.moduleLoadProgress = 1
                    self.moduleStatus = .loaded
                    self.diagnostics.info("engine warmup finished")
                }
            } catch {
                let errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                await MainActor.run {
                    self.diagnostics.endInterval("EngineWarmup", interval)
                    self.moduleLoadProgress = 0
                    self.moduleStatus = .failed(errorText)
                    self.diagnostics.error("engine warmup failed: \(errorText)")
                }
            }
        }
    }

    func unloadEngine() {
        queueTransition(phase: .stopping, action: .stop) {
            await self.stopGeneration(resetEngine: true)
            self.moduleStatus = .notLoaded
            self.moduleLoadProgress = 0
        }
    }

    func renameConversation(id: UUID, title: String) {
        guard let idx = storedConversations.firstIndex(where: { $0.id == id }) else { return }
        let normalized = Self.normalizeManualTitle(title)
        storedConversations[idx].overrideTitle = normalized
        refreshHistoryItems()
        persistStore(reason: .renameConversation)
    }

    func generateTitleForConversation(id: UUID, pinResult: Bool) {
        startTitleGenerationTask(for: id, pinResult: pinResult, forceRegenerate: true)
    }

    func isGeneratingTitle(for id: UUID) -> Bool {
        titleGeneratingConversationIDs.contains(id)
    }

    func deleteConversation(id: UUID) {
        titleGenerationTasks[id]?.cancel()
        titleGenerationTasks[id] = nil
        titleGeneratingConversationIDs.remove(id)
        storedConversations.removeAll { $0.id == id }
        if activeConversationID == id {
            activeConversationID = nil
            messages.removeAll()
            restoreThinkingDefaults()
        }
        refreshHistoryItems()
        persistStore(reason: .deleteConversation)
    }

    func isCurrentConversation(_ id: UUID) -> Bool {
        activeConversationID == id
    }

    func isThinkingExpanded(for messageID: UUID, isStreaming: Bool) -> Bool {
        if isStreaming {
            return isStreamingThinkingExpanded
        }
        return expandedThinkingMessageIDs.contains(messageID)
    }

    func toggleThinkingExpansion(for messageID: UUID, isStreaming: Bool) {
        recordAction(.toggleThinking(isStreaming: isStreaming))
        guard canToggleThinkingDetails else {
            recordBlockedAction("thinking toggle while \(sessionPhase.rawValue)")
            return
        }

        let now = Date().timeIntervalSinceReferenceDate
        guard now - lastThinkingToggleAt >= Self.thinkingToggleCooldown else {
            recordBlockedAction("thinking toggle cooldown")
            return
        }

        lastThinkingToggleAt = now
        debugStats.thinkingToggleCount += 1

        if isStreaming {
            isStreamingThinkingExpanded.toggle()
            return
        }

        if expandedThinkingMessageIDs.contains(messageID) {
            expandedThinkingMessageIDs.remove(messageID)
        } else {
            expandedThinkingMessageIDs.insert(messageID)
        }
    }

    private func beginGeneration(userText: String, imageDataList: [Data]) {
        isGenerating = true
        sessionPhase = .generating
        restoreThinkingDefaults()
        currentGenerationID = UUID()
        currentGenerationInterval = diagnostics.beginInterval("Generation")
        activeGenerationReasoningMode = reasoningMode

        let currentMode = mode
        let currentTranslationSettings = translationSettings
        let generationID = currentGenerationID!
        let promptMessages = makePromptMessages(
            mode: currentMode,
            userInput: userText,
            translationSettings: currentTranslationSettings
        )

        if moduleStatus != .loaded {
            moduleStatus = .loading
            moduleLoadProgress = 0
        }

        messages.append(Message(role: .user, content: userText, imageAttachments: imageDataList))
        persistCurrentConversation(reason: .send)
        resetStreamingState()

        // Force noThinking when images are attached to avoid model hang with multimodal + thinking
        let hasImages = !imageDataList.filter({ !$0.isEmpty }).isEmpty
        currentGenerationHasImages = hasImages
        pendingStopDuringImageProcessing = false
        showsImageProcessingPlaceholder = hasImages
        let effectiveReasoningMode: ReasoningMode = hasImages ? .noThinking : reasoningMode
        activeGenerationReasoningMode = effectiveReasoningMode

        let inferenceProfile: InferenceProfile = effectiveReasoningMode.isThinkingEnabled
            ? .chat
            : (currentMode == .translation ? .translation : .chat)
        let generationConfig = currentMode == .chat ? chatStyle.generationConfig : nil
        let contextTokens = Int32(contextLength.tokenCount)

        runningTask = Task { [weak self] in
            await self?.runGeneration(
                generationID: generationID,
                promptMessages: promptMessages,
                imageDataList: imageDataList,
                contextTokens: contextTokens,
                reasoningMode: effectiveReasoningMode,
                profile: inferenceProfile,
                generationConfig: generationConfig
            )
        }
    }

    private func runGeneration(
        generationID: UUID,
        promptMessages: [PromptMessage],
        imageDataList: [Data],
        contextTokens: Int32,
        reasoningMode: ReasoningMode,
        profile: InferenceProfile,
        generationConfig: GenerationConfig?
    ) async {
        let tokenBuffer = StreamingTokenBuffer()

        func flushBufferedTokens() async {
            let chunk = await tokenBuffer.drain()
            guard !chunk.isEmpty else { return }
            await MainActor.run {
                guard self.currentGenerationID == generationID else { return }
                self.appendStreamingPiece(chunk)
            }
        }

        let bridgeTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Self.streamingTokenFlushInterval * 1_000_000_000))
                await flushBufferedTokens()
            }
        }

        defer { bridgeTask.cancel() }

        do {
            let result = try await engine.generate(
                messages: promptMessages,
                imageDataList: imageDataList,
                contextLength: contextTokens,
                reasoningMode: reasoningMode,
                profile: profile,
                generationConfig: generationConfig,
                onLoadProgress: { progress in
                    await MainActor.run {
                        guard self.currentGenerationID == generationID else { return }
                        self.handleModuleLoadProgress(progress)
                    }
                },
                onToken: { token in
                    await tokenBuffer.append(token)
                }
            )
            await flushBufferedTokens()
            await MainActor.run {
                guard self.currentGenerationID == generationID else { return }
                self.flushStreamingPreview(force: true)
                self.moduleLoadProgress = 1
                self.moduleStatus = .loaded

                let parsed = Self.splitThinking(
                    from: result,
                    assumeStartsInThinking: reasoningMode.isThinkingEnabled
                )
                let hasAnyOutput = !parsed.answer.isEmpty || !parsed.thinking.isEmpty
                let answer = hasAnyOutput ? parsed.answer : "（没有生成内容）"
                let thinking = parsed.thinking.isEmpty ? nil : parsed.thinking
                let assistantThinking = reasoningMode.isThinkingEnabled ? thinking : nil

                self.messages.append(Message(role: .assistant, content: answer, thinking: assistantThinking))
                self.persistCurrentConversation(reason: .completion)
                self.finishGeneration(generationID: generationID)
                self.generateTitleForActiveConversationIfNeeded()
            }
        } catch is CancellationError {
            diagnostics.info("generation cancelled")
        } catch {
            await flushBufferedTokens()
            let errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            await MainActor.run {
                guard self.currentGenerationID == generationID else { return }
                self.moduleLoadProgress = 0
                self.moduleStatus = .failed(errorText)
                self.messages.append(Message(role: .assistant, content: "推理失败：\(errorText)"))
                self.persistCurrentConversation(reason: .completion)
                self.finishGeneration(generationID: generationID)
                self.generateTitleForActiveConversationIfNeeded()
                self.diagnostics.error("generation failed: \(errorText)")
            }
        }
    }

    private func finishGeneration(generationID: UUID) {
        guard currentGenerationID == generationID else { return }
        currentGenerationID = nil
        runningTask = nil
        isGenerating = false
        activeGenerationReasoningMode = nil
        resetStreamingState()
        sessionPhase = .idle
        if let interval = currentGenerationInterval {
            diagnostics.endInterval("Generation", interval)
            currentGenerationInterval = nil
        }
    }

    private func queueTransition(
        phase: ConversationPhase,
        action: ChatAction,
        operation: @escaping @MainActor () async -> Void
    ) {
        guard transitionTask == nil else {
            recordBlockedAction("blocked \(action.description)")
            return
        }

        sessionPhase = phase
        let intervalName: StaticString = {
            switch phase {
            case .stopping: return "StopTransition"
            case .switchingMode: return "ModeSwitchTransition"
            case .restoring: return "RestoreTransition"
            case .idle, .generating: return "IdleTransition"
            }
        }()
        let interval = diagnostics.beginInterval(intervalName)

        transitionTask = Task { [weak self] in
            guard self != nil else { return }
            await operation()
            await MainActor.run {
                self?.diagnostics.endInterval(intervalName, interval)
                self?.transitionTask = nil
                if self?.isGenerating == false {
                    self?.sessionPhase = .idle
                }
            }
        }
    }

    private func stopGeneration(resetEngine: Bool, savePartial: Bool = false) async {
        let generationID = currentGenerationID
        currentGenerationID = nil

        let task = runningTask
        runningTask = nil

        if generationID != nil {
            await engine.stop()
            task?.cancel()
            if let task {
                _ = await task.result
            }

            if savePartial {
                flushStreamingPreview(force: true)
                let wasThinking = activeGenerationReasoningMode?.isThinkingEnabled == true
                savePartialGenerationOutput(wasThinking: wasThinking)
            }
        }

        activeGenerationReasoningMode = nil

        if let interval = currentGenerationInterval {
            diagnostics.endInterval("Generation", interval)
            currentGenerationInterval = nil
        }

        if resetEngine {
            await engine.reset()
            moduleLoadProgress = 0
        }

        isGenerating = false
        resetStreamingState()
    }

    private func restoreMode(_ newMode: ChatMode) {
        mode = newMode
        historyModeFilter = newMode
        restoreThinkingDefaults()

        if let latest = latestConversation(for: newMode) {
            applyConversationRecord(latest)
            return
        }

        activeConversationID = nil
        messages.removeAll()
        if newMode == .translation {
            translationSettings = latestTranslationSettings() ?? .default
        }
    }

    private func appendStreamingPiece(_ piece: String) {
        if currentGenerationHasImages, !piece.isEmpty {
            showsImageProcessingPlaceholder = false
            if pendingStopDuringImageProcessing {
                pendingStopDuringImageProcessing = false
                Task { @MainActor [weak self] in
                    self?.stop()
                }
                return
            }
        }
        streamingRawText += piece
        flushStreamingPreview(force: false)
    }

    private func flushStreamingPreview(force: Bool) {
        let now = Date().timeIntervalSinceReferenceDate
        if force || now - lastStreamingRefreshAt >= Self.streamingRefreshInterval {
            pendingStreamingRefreshTask?.cancel()
            pendingStreamingRefreshTask = nil
            lastStreamingRefreshAt = now
            debugStats.streamingRefreshCount += 1

            let mode = activeGenerationReasoningMode ?? reasoningMode
            let parsed = Self.splitThinking(
                from: streamingRawText,
                assumeStartsInThinking: mode.isThinkingEnabled
            )
            currentStreamingText = parsed.answer
            currentStreamingThinking = mode.isThinkingEnabled ? parsed.thinking : ""
            return
        }

        guard pendingStreamingRefreshTask == nil else { return }
        let delay = Self.streamingRefreshInterval - (now - lastStreamingRefreshAt)
        pendingStreamingRefreshTask = Task { [weak self] in
            let safeDelay = max(0, delay)
            try? await Task.sleep(nanoseconds: UInt64(safeDelay * 1_000_000_000))
            await MainActor.run {
                self?.performPendingStreamingRefresh()
            }
        }
    }

    private func performPendingStreamingRefresh() {
        pendingStreamingRefreshTask = nil
        flushStreamingPreview(force: true)
    }

    private func resetStreamingState() {
        pendingStreamingRefreshTask?.cancel()
        pendingStreamingRefreshTask = nil
        lastStreamingRefreshAt = 0
        streamingRawText = ""
        currentStreamingText = ""
        currentStreamingThinking = ""
        showsImageProcessingPlaceholder = false
        currentGenerationHasImages = false
        pendingStopDuringImageProcessing = false
        isStreamingThinkingExpanded = false
    }

    private func savePartialGenerationOutput(wasThinking: Bool) {
        if currentGenerationHasImages,
           !wasThinking,
           streamingRawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messages.append(Message(role: .assistant, content: localizedStoppedImageAnalysisMessage()))
            persistCurrentConversation(reason: .completion)
            generateTitleForActiveConversationIfNeeded()
            return
        }

        guard !streamingRawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        if wasThinking {
            if currentStreamingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // Interrupted during thinking phase, before any answer output
                messages.append(Message(role: .assistant, content: localizedStoppedThinkingMessage()))
            } else {
                // Interrupted during answer output - preserve partial answer with thinking
                let thinking: String? = currentStreamingThinking.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? nil : currentStreamingThinking
                messages.append(Message(role: .assistant, content: currentStreamingText, thinking: thinking))
            }
        } else {
            guard !currentStreamingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            messages.append(Message(role: .assistant, content: currentStreamingText))
        }

        persistCurrentConversation(reason: .completion)
        generateTitleForActiveConversationIfNeeded()
    }

    private func localizedStoppedThinkingMessage() -> String {
        LocalizationCatalog.text(.assistantStoppedThinking, language: AppLanguage.storedLanguage())
    }

    private func localizedStoppedImageAnalysisMessage() -> String {
        LocalizationCatalog.text(.attachmentImageProcessingStopped, language: AppLanguage.storedLanguage())
    }

    private func restoreThinkingDefaults() {
        expandedThinkingMessageIDs.removeAll()
        isStreamingThinkingExpanded = false
    }

    private func restoreConversationStore() {
        guard let data = try? Data(contentsOf: historyURL) else { return }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let store = try? decoder.decode(ConversationStore.self, from: data) {
            applyConversationStore(store)
            return
        }

        if let legacy = try? decoder.decode(LegacyConversationSnapshot.self, from: data) {
            migrateLegacySnapshot(legacy)
        }
    }

    private func enforceChatOnlyPresentation() {
        mode = .chat
        historyModeFilter = .chat

        activeConversationID = nil
        messages.removeAll()
        chatDraft = ""
        translationDraft = ""
        if let latestChat = latestConversation(for: .chat) {
            contextLength = latestChat.contextLength
        }
        restoreThinkingDefaults()
        refreshHistoryItems()
    }

    private func applyConversationStore(_ store: ConversationStore) {
        storedConversations = store.conversations.sorted { $0.updatedAt > $1.updatedAt }
        mode = store.activeMode ?? .chat
        historyModeFilter = mode
        translationSettings = store.activeTranslationSettings ?? latestTranslationSettings() ?? .default
        activeConversationID = nil
        messages.removeAll()
        chatDraft = ""
        translationDraft = ""
        restoreThinkingDefaults()

        if let restoredID = store.activeConversationID,
           let restored = storedConversations.first(where: { $0.id == restoredID }) {
            applyConversationRecord(restored)
        } else if let latestInMode = latestConversation(for: mode) {
            contextLength = latestInMode.contextLength
            if let settings = latestInMode.translationSettings {
                translationSettings = settings
            }
        } else if let latest = storedConversations.first {
            contextLength = latest.contextLength
        }

        refreshHistoryItems()
    }

    private func migrateLegacySnapshot(_ legacy: LegacyConversationSnapshot) {
        contextLength = legacy.contextLength
        messages.removeAll()

        if !legacy.messages.isEmpty {
            let record = ConversationRecord(
                id: UUID(),
                createdAt: legacy.savedAt,
                updatedAt: legacy.savedAt,
                mode: .chat,
                translationSettings: nil,
                contextLength: legacy.contextLength,
                messages: legacy.messages,
                overrideTitle: nil,
                aiTitle: nil,
                legacyTitle: Self.makeConversationTitle(from: legacy.messages)
            )
            storedConversations = [record]
        }

        activeConversationID = nil
        mode = .chat
        historyModeFilter = .chat
        translationSettings = .default
        chatDraft = ""
        translationDraft = ""
        restoreThinkingDefaults()
        refreshHistoryItems()
        persistStore(reason: .restore)
    }

    private func makePromptMessages(
        mode: ChatMode,
        userInput: String,
        translationSettings: TranslationSettings
    ) -> [PromptMessage] {
        switch mode {
        case .chat:
            // Build multi-turn conversation context:
            // - Only text content (images from previous messages excluded)
            // - Thinking content excluded (only message.content, not message.thinking)
            var promptMessages: [PromptMessage] = []
            if let systemPrompt = chatStyle.systemPrompt(appLanguage: AppLanguage.storedLanguage()) {
                promptMessages.append(PromptMessage(role: .system, content: systemPrompt))
            }
            for message in messages {
                let role: PromptRole = message.role == .user ? .user : .assistant
                promptMessages.append(PromptMessage(role: role, content: message.content))
            }
            promptMessages.append(PromptMessage(role: .user, content: userInput))
            return promptMessages
        case .translation:
            return TranslationPromptFactory.makeMessages(input: userInput, settings: translationSettings)
        }
    }

    private func latestConversation(for mode: ChatMode) -> ConversationRecord? {
        storedConversations
            .filter { $0.mode == mode }
            .sorted { $0.updatedAt > $1.updatedAt }
            .first
    }

    private func latestTranslationSettings() -> TranslationSettings? {
        storedConversations.first(where: { $0.mode == .translation && $0.translationSettings != nil })?.translationSettings
    }

    private func applyConversationRecord(_ record: ConversationRecord) {
        activeConversationID = record.id
        messages = record.messages
        contextLength = record.contextLength
        mode = record.mode
        historyModeFilter = record.mode
        if let settings = record.translationSettings {
            translationSettings = settings
        } else if record.mode == .translation {
            translationSettings = latestTranslationSettings() ?? .default
        }
        setDraft("", for: record.mode)
        restoreThinkingDefaults()
        refreshHistoryItems()
    }

    private func setDraft(_ text: String, for mode: ChatMode) {
        switch mode {
        case .chat:
            chatDraft = text
        case .translation:
            translationDraft = text
        }
    }

    private func handleTranslationSettingsChanged() {
        guard mode == .translation else { return }

        if let activeConversationID,
           let index = storedConversations.firstIndex(where: { $0.id == activeConversationID }) {
            storedConversations[index].mode = .translation
            storedConversations[index].translationSettings = translationSettings
            storedConversations[index].updatedAt = Date()
            storedConversations.sort { $0.updatedAt > $1.updatedAt }
            refreshHistoryItems()
        }

        persistStore(reason: .translationSettings)
    }

    private func persistCurrentConversation(reason: PersistenceReason) {
        guard !messages.isEmpty else {
            persistStore(reason: reason)
            return
        }

        let now = Date()
        let conversationID = activeConversationID ?? UUID()
        activeConversationID = conversationID

        if let idx = storedConversations.firstIndex(where: { $0.id == conversationID }) {
            storedConversations[idx].messages = messages
            storedConversations[idx].contextLength = contextLength
            storedConversations[idx].updatedAt = now
            storedConversations[idx].mode = mode
            storedConversations[idx].translationSettings = mode == .translation ? translationSettings : nil
            if storedConversations[idx].legacyTitle == nil {
                storedConversations[idx].legacyTitle = Self.makeConversationTitle(from: messages)
            }
        } else {
            let record = ConversationRecord(
                id: conversationID,
                createdAt: now,
                updatedAt: now,
                mode: mode,
                translationSettings: mode == .translation ? translationSettings : nil,
                contextLength: contextLength,
                messages: messages,
                overrideTitle: nil,
                aiTitle: nil,
                legacyTitle: Self.makeConversationTitle(from: messages)
            )
            storedConversations.append(record)
        }

        storedConversations.sort { $0.updatedAt > $1.updatedAt }
        refreshHistoryItems()
        persistStore(reason: reason)
    }

    private func persistStore(reason: PersistenceReason) {
        recordAction(.persistence(reason))

        storedConversations = storedConversations
            .filter { !$0.messages.isEmpty }
            .sorted { $0.updatedAt > $1.updatedAt }

        if let activeConversationID,
           !storedConversations.contains(where: { $0.id == activeConversationID }) {
            self.activeConversationID = nil
        }

        refreshHistoryItems()

        let store = ConversationStore(
            version: 4,
            savedAt: Date(),
            activeConversationID: activeConversationID,
            activeMode: mode,
            activeTranslationSettings: translationSettings,
            conversations: storedConversations
        )
        let targetURL = historyURL
        pendingPersistenceWorkItem?.cancel()

        let workItem = DispatchWorkItem { [diagnostics] in
            let interval = diagnostics.beginInterval("PersistenceWrite")
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

            guard let data = try? encoder.encode(store) else {
                diagnostics.endInterval("PersistenceWrite", interval)
                diagnostics.error("persistence encode failed")
                return
            }

            do {
                try data.write(to: targetURL, options: .atomic)
                diagnostics.endInterval("PersistenceWrite", interval)
                diagnostics.info("persistence checkpoint completed: \(reason.rawValue)")
            } catch {
                diagnostics.endInterval("PersistenceWrite", interval)
                diagnostics.error("persistence write failed: \(error.localizedDescription)")
            }
        }

        pendingPersistenceWorkItem = workItem
        persistenceQueue.async(execute: workItem)
    }

    private func refreshHistoryItems() {
        historyItems = storedConversations
            .sorted { $0.updatedAt > $1.updatedAt }
            .filter { $0.mode == .chat }
            .map { record in
                ConversationHistoryItem(
                    id: record.id,
                    title: resolvedTitle(for: record),
                    updatedAt: record.updatedAt,
                    messageCount: record.messages.count,
                    mode: record.mode
                )
            }
    }

    private func resolvedTitle(for record: ConversationRecord) -> String {
        if let overridden = Self.normalizeManualTitle(record.overrideTitle) {
            return overridden
        }

        if titleMode == .aiGenerated, let cachedAI = Self.normalizeManualTitle(record.aiTitle) {
            return cachedAI
        }

        return Self.makeConversationTitle(from: record.messages)
    }

    private static func makeConversationTitle(from messages: [Message]) -> String {
        let content = messages.first(where: {
            $0.role == .user && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        })?.content
        ?? messages.first(where: {
            !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        })?.content
        ?? LocalizationCatalog.text(.sidebarNewConversation, language: AppLanguage.storedLanguage())

        return compact(content, limit: 24)
    }

    private static func normalizeManualTitle(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        return normalized.isEmpty ? nil : compact(normalized, limit: 24)
    }

    private static func compact(_ text: String, limit: Int) -> String {
        let compacted = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard compacted.count > limit else { return compacted }
        return String(compacted.prefix(limit)) + "…"
    }

    private func prefetchMissingAITitlesIfNeeded() {
        guard titleMode == .aiGenerated else { return }
        guard !isGenerating, transitionTask == nil else { return }

        for record in storedConversations.filter({ $0.mode == .chat }).prefix(8) {
            guard Self.normalizeManualTitle(record.overrideTitle) == nil else { continue }
            startTitleGenerationTask(for: record.id, pinResult: false, forceRegenerate: false)
        }
    }

    private func startTitleGenerationTask(for id: UUID, pinResult: Bool, forceRegenerate: Bool) {
        guard titleGenerationTasks[id] == nil else { return }
        guard sessionPhase != .generating else { return }
        guard let record = storedConversations.first(where: { $0.id == id }) else { return }
        guard !record.messages.isEmpty else { return }
        if !forceRegenerate, Self.normalizeManualTitle(record.overrideTitle) != nil { return }
        if !forceRegenerate, Self.normalizeManualTitle(record.aiTitle) != nil { return }

        let source = ConversationTitleGenerator.firstUserMessage(in: record.messages)
        guard !source.isEmpty else { return }

        titleGeneratingConversationIDs.insert(id)

        let task = Task { [weak self] in
            guard let self else { return }

            do {
                let generated = try await self.generateTitleFromFirstUserMessage(source)
                await MainActor.run {
                    guard let idx = self.storedConversations.firstIndex(where: { $0.id == id }) else { return }
                    self.storedConversations[idx].aiTitle = generated
                    if pinResult {
                        self.storedConversations[idx].overrideTitle = generated
                    }
                    self.refreshHistoryItems()
                    self.persistStore(reason: .titleGeneration)
                    self.titleGeneratingConversationIDs.remove(id)
                    self.titleGenerationTasks[id] = nil
                }
            } catch {
                await MainActor.run {
                    self.titleGeneratingConversationIDs.remove(id)
                    self.titleGenerationTasks[id] = nil
                }
            }
        }

        titleGenerationTasks[id] = task
    }

    private func generateTitleFromFirstUserMessage(_ firstUserMessage: String) async throws -> String {
        let titleCtx = ConversationTitleGenerator.titleContextLength
        let userCtx = contextLength
        let needsReload = userCtx != .enhanced // .enhanced == 16K

        if needsReload {
            await engine.reset()
        }

        let language = AppLanguage.storedLanguage()
        let raw: String
        do {
            raw = try await engine.generate(
                messages: ConversationTitleGenerator.promptMessages(for: firstUserMessage, language: language),
                imageData: nil,
                contextLength: titleCtx,
                reasoningMode: .noThinking,
                profile: .chat,
                maxTokens: 32,
                onToken: nil
            )
        } catch {
            if needsReload {
                await engine.reset()
            }
            throw error
        }

        if needsReload {
            await engine.reset()
            await MainActor.run {
                self.moduleStatus = .notLoaded
                self.moduleLoadProgress = 0
            }
        }

        let cleaned = ConversationTitleGenerator.cleanup(raw)
        if cleaned.isEmpty {
            return Self.makeConversationTitle(from: [Message(role: .user, content: firstUserMessage)])
        }
        return cleaned
    }

    private func generateTitleForActiveConversationIfNeeded() {
        guard titleMode == .aiGenerated else { return }
        guard let activeConversationID else { return }
        startTitleGenerationTask(for: activeConversationID, pinResult: false, forceRegenerate: false)
    }

    private static func splitThinking(
        from raw: String,
        assumeStartsInThinking: Bool = false
    ) -> (answer: String, thinking: String) {
        if assumeStartsInThinking,
           earliestTag(in: raw, from: raw.startIndex, tags: thinkStartTags) == nil {
            if let end = earliestTag(in: raw, from: raw.startIndex, tags: thinkEndTags) {
                let thinking = String(raw[..<end.range.lowerBound])
                let answer = String(raw[end.range.upperBound...])
                let cleanedAnswer = cleanupThinkingArtifacts(answer, stripPartialTag: true)
                let cleanedThinking = cleanupThinkingArtifacts(thinking, stripPartialTag: false)
                return (cleanedAnswer, cleanedThinking)
            }
            let cleanedThinking = cleanupThinkingArtifacts(raw, stripPartialTag: false)
            return ("", cleanedThinking)
        }

        var answer = ""
        var thinking = ""
        var cursor = raw.startIndex

        while cursor < raw.endIndex {
            guard let start = earliestTag(in: raw, from: cursor, tags: thinkStartTags) else {
                answer += String(raw[cursor...])
                break
            }

            answer += String(raw[cursor..<start.range.lowerBound])

            if let end = earliestTag(in: raw, from: start.range.upperBound, tags: thinkEndTags) {
                thinking += String(raw[start.range.upperBound..<end.range.lowerBound])
                cursor = end.range.upperBound
            } else {
                thinking += String(raw[start.range.upperBound...])
                cursor = raw.endIndex
            }
        }

        return (
            cleanupThinkingArtifacts(answer, stripPartialTag: true),
            cleanupThinkingArtifacts(thinking, stripPartialTag: false)
        )
    }

    private static func earliestTag(
        in text: String,
        from start: String.Index,
        tags: [String]
    ) -> (tag: String, range: Range<String.Index>)? {
        var bestTag: String?
        var bestRange: Range<String.Index>?

        for tag in tags {
            guard let range = text.range(of: tag, options: .caseInsensitive, range: start..<text.endIndex) else {
                continue
            }
            if let existingBestRange = bestRange {
                if range.lowerBound < existingBestRange.lowerBound {
                    bestRange = range
                    bestTag = tag
                }
            } else {
                bestRange = range
                bestTag = tag
            }
        }

        guard let bestTag, let bestRange else { return nil }
        return (bestTag, bestRange)
    }

    private static func cleanupThinkingArtifacts(_ text: String, stripPartialTag: Bool) -> String {
        var cleaned = text
        let tagPatterns = [
            #"</?\s*think\s*>"#,
            #"</?\s*thinking\s*>"#,
            #"</?\s*reasoning\s*>"#,
            #"</?\s*analysis\s*>"#
        ]
        for pattern in tagPatterns {
            cleaned = cleaned.replacingOccurrences(
                of: pattern,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        if stripPartialTag {
            cleaned = stripTrailingPartialTag(from: cleaned)
        }
        return cleaned
    }

    private static func stripTrailingPartialTag(from text: String) -> String {
        var result = text
        let tags = thinkStartTags + thinkEndTags

        var changed = true
        while changed {
            changed = false
            let lowerResult = result.lowercased()
            for tag in tags where tag.count > 1 {
                let lowerTag = tag.lowercased()
                for length in stride(from: tag.count - 1, through: 1, by: -1) {
                    let fragment = String(lowerTag.prefix(length))
                    guard lowerResult.hasSuffix(fragment) else { continue }
                    result.removeLast(length)
                    changed = true
                    break
                }
                if changed { break }
            }
        }

        return result
    }

    private static func makeHistoryURL() -> URL {
        let fileManager = FileManager.default
        let baseDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let appDir = baseDir.appendingPathComponent("localAI", isDirectory: true)
        try? fileManager.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir.appendingPathComponent("chat_history.json")
    }

    static func deleteAllLocalHistory() {
        let historyURL = makeHistoryURL()
        try? FileManager.default.removeItem(at: historyURL)
        NotificationCenter.default.post(name: .localAIHistoryReset, object: nil)
    }

    static func restoreDefaultSettings() {
        let defaults = UserDefaults.standard
        defaults.set(AppLanguage.autoStorageValue, forKey: AppLanguage.storageKey)
        defaults.set(AppAppearanceMode.system.rawValue, forKey: AppAppearanceMode.storageKey)
        defaults.set(ChatTitleMode.content.rawValue, forKey: ChatTitleMode.storageKey)
        defaults.set(ChatStyle.defaultStyle.rawValue, forKey: ChatStyle.storageKey)
        defaults.set(false, forKey: Self.thinkingModeUnlockedKey)
        defaults.set(ReasoningMode.noThinking.rawValue, forKey: Self.reasoningModePreferenceKey)
        NotificationCenter.default.post(name: .localAIDefaultSettingsReset, object: nil)
    }

    private func observeExternalSettingsChanges() {
        NotificationCenter.default.publisher(for: .localAIHistoryReset)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.handleExternalHistoryReset()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .localAIDefaultSettingsReset)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.handleDefaultSettingsReset()
            }
            .store(in: &cancellables)
    }

    private func handleExternalHistoryReset() {
        queueTransition(phase: .restoring, action: .newConversation) {
            await self.stopGeneration(resetEngine: false)
            self.storedConversations.removeAll()
            self.activeConversationID = nil
            self.messages.removeAll()
            self.currentStreamingText = ""
            self.currentStreamingThinking = ""
            self.restoreThinkingDefaults()
            self.refreshHistoryItems()
            self.persistStore(reason: .deleteConversation)
        }
    }

    private func handleDefaultSettingsReset() {
        queueTransition(phase: .restoring, action: .changeContextLength(.enhanced)) {
            await self.stopGeneration(resetEngine: true)
            self.contextLength = .enhanced
            self.moduleStatus = .notLoaded
            self.moduleLoadProgress = 0
            self.setThinkingModeUnlocked(false)
            self.updateReasoningMode(.noThinking)
            if let activeConversationID = self.activeConversationID,
               let index = self.storedConversations.firstIndex(where: { $0.id == activeConversationID }) {
                self.storedConversations[index].contextLength = .enhanced
                self.storedConversations[index].updatedAt = Date()
                self.storedConversations.sort { $0.updatedAt > $1.updatedAt }
            }
            self.persistStore(reason: .contextLength)
        }
    }

    private func recordAction(_ action: ChatAction) {
        debugStats.lastActionDescription = action.description
        diagnostics.info("action: \(action.description)")
    }

    private func recordBlockedAction(_ reason: String) {
        debugStats.blockedActionCount += 1
        diagnostics.info("blocked action: \(reason)")
    }
}
