import Foundation
import llama

nonisolated enum PromptRole: String, Sendable {
    case system
    case user
    case assistant
}

nonisolated struct PromptMessage: Sendable {
    var role: PromptRole
    var content: String
}

nonisolated enum InferenceProfile: Sendable {
    case chat
    case translation
}

nonisolated struct GenerationConfig: Sendable, Equatable {
    let temperature: Float
    let topP: Float
    let topK: Int32

    static func defaults(for profile: InferenceProfile) -> GenerationConfig {
        switch profile {
        case .chat:
            return GenerationConfig(temperature: 0.7, topP: 0.92, topK: 40)
        case .translation:
            return GenerationConfig(temperature: 0.2, topP: 0.95, topK: 40)
        }
    }
}

nonisolated enum LlamaEngineError: LocalizedError {
    case modelUnavailable(String)
    case multimodalUnavailable(String)
    case inferenceFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelUnavailable(let reason):
            return "模型不可用：\(reason)"
        case .multimodalUnavailable(let reason):
            return "多模态不可用：\(reason)"
        case .inferenceFailed(let reason):
            return "推理失败：\(reason)"
        }
    }
}

nonisolated final class ModelLoadProgressRelay: @unchecked Sendable {
    private let handler: @Sendable (Double) -> Void
    private let lock = NSLock()
    private var lastReported: Double = -1

    init(handler: @escaping @Sendable (Double) -> Void) {
        self.handler = handler
    }

    func report(_ progress: Float) {
        let clamped = min(max(Double(progress), 0), 1)
        let mapped = min(0.9, clamped * 0.9)
        lock.lock()
        defer { lock.unlock() }
        guard mapped >= 1 || mapped - lastReported >= 0.01 else { return }
        lastReported = mapped
        handler(mapped)
    }
}

actor LlamaMultimodalEngine {
    private static let modelName = "Qwen3.5-2B-Q4_K_M"
    private static let modelExt = "gguf"
    private static let mmprojName = "mmproj-BF16"
    private static let mmprojExt = "gguf"
    private static let mediaMarker = "<__media__>"
    private static let legacyImageMarker = "<__image__>"

    private var runtime: EmbeddedLlamaRuntime?
    private var runtimeContextLength: Int32 = 0
    private var stopRequested = false

    func isLoaded() -> Bool {
        runtime != nil
    }

    func warmup(
        contextLength: Int32,
        onLoadProgress: (@Sendable (Double) async -> Void)? = nil
    ) async throws {
        _ = try ensureRuntime(contextLength: contextLength, onLoadProgress: onLoadProgress)
    }

    func stop() {
        stopRequested = true
    }

    func reset() {
        stopRequested = false
        runtime = nil
        runtimeContextLength = 0
    }

    func generate(
        prompt: String,
        imageData: Data?,
        contextLength: Int32,
        reasoningMode: ReasoningMode,
        profile: InferenceProfile = .chat,
        generationConfig: GenerationConfig? = nil,
        maxTokens: Int32 = 0,
        onLoadProgress: (@Sendable (Double) async -> Void)? = nil,
        onToken: (@Sendable (String) async -> Void)? = nil
    ) async throws -> String {
        try await generate(
            messages: [PromptMessage(role: .user, content: prompt)],
            imageDataList: imageData.map { [$0] } ?? [],
            contextLength: contextLength,
            reasoningMode: reasoningMode,
            profile: profile,
            generationConfig: generationConfig,
            maxTokens: maxTokens,
            onLoadProgress: onLoadProgress,
            onToken: onToken
        )
    }

    func generate(
        messages: [PromptMessage],
        imageData: Data?,
        contextLength: Int32,
        reasoningMode: ReasoningMode,
        profile: InferenceProfile = .chat,
        generationConfig: GenerationConfig? = nil,
        maxTokens: Int32 = 0,
        onLoadProgress: (@Sendable (Double) async -> Void)? = nil,
        onToken: (@Sendable (String) async -> Void)? = nil
    ) async throws -> String {
        try await generate(
            messages: messages,
            imageDataList: imageData.map { [$0] } ?? [],
            contextLength: contextLength,
            reasoningMode: reasoningMode,
            profile: profile,
            generationConfig: generationConfig,
            maxTokens: maxTokens,
            onLoadProgress: onLoadProgress,
            onToken: onToken
        )
    }

    func generate(
        messages: [PromptMessage],
        imageDataList: [Data],
        contextLength: Int32,
        reasoningMode: ReasoningMode,
        profile: InferenceProfile = .chat,
        generationConfig: GenerationConfig? = nil,
        maxTokens: Int32 = 0,
        onLoadProgress: (@Sendable (Double) async -> Void)? = nil,
        onToken: (@Sendable (String) async -> Void)? = nil
    ) async throws -> String {
        stopRequested = false
        let normalizedImageDataList = imageDataList.filter { !$0.isEmpty }

        let runtime = try ensureRuntime(contextLength: contextLength, onLoadProgress: onLoadProgress)
        let prompt = try await runtime.formatPrompt(
            messages: normalized(messages, mediaCount: normalizedImageDataList.count),
            reasoningMode: reasoningMode,
            profile: profile
        )

        let resolvedMaxTokens = resolveMaxTokens(
            requested: maxTokens,
            contextLength: contextLength,
            profile: profile,
            reasoningMode: reasoningMode
        )

        return try await runtime.generate(
            prompt: prompt,
            imageDataList: normalizedImageDataList,
            maxTokens: resolvedMaxTokens,
            profile: profile,
            generationConfig: generationConfig ?? GenerationConfig.defaults(for: profile),
            onToken: onToken
        )
    }

    private func normalized(_ messages: [PromptMessage], mediaCount: Int) -> [PromptMessage] {
        let compact = messages
            .map { PromptMessage(role: $0.role, content: $0.content.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.content.isEmpty }

        let normalizedMessages: [PromptMessage]
        if compact.isEmpty {
            normalizedMessages = [PromptMessage(role: .user, content: "")]
        } else {
            normalizedMessages = compact
        }

        guard mediaCount > 0 else {
            return normalizedMessages
        }

        return attachMediaMarkers(to: normalizedMessages, count: mediaCount)
    }

    private func attachMediaMarkers(to messages: [PromptMessage], count: Int) -> [PromptMessage] {
        var updated = messages

        if let lastUserIndex = updated.lastIndex(where: { $0.role == .user }) {
            let current = updated[lastUserIndex].content
            let existingMarkerCount = mediaMarkerCount(in: current)
            if existingMarkerCount >= count {
                return updated
            }
            let appendedMarkers = Array(repeating: Self.mediaMarker, count: count - existingMarkerCount).joined(separator: "\n")
            let injected = current.isEmpty ? appendedMarkers : "\(current)\n\(appendedMarkers)"
            updated[lastUserIndex].content = injected
            return updated
        }

        updated.append(
            PromptMessage(
                role: .user,
                content: Array(repeating: Self.mediaMarker, count: count).joined(separator: "\n")
            )
        )
        return updated
    }

    private func mediaMarkerCount(in text: String) -> Int {
        max(0, text.components(separatedBy: Self.mediaMarker).count - 1)
        + max(0, text.components(separatedBy: Self.legacyImageMarker).count - 1)
    }

    private func ensureRuntime(
        contextLength: Int32,
        onLoadProgress: (@Sendable (Double) async -> Void)? = nil
    ) throws -> EmbeddedLlamaRuntime {
        if let runtime, contextLength == runtimeContextLength {
            return runtime
        }

        guard let modelURL = Bundle.main.url(forResource: Self.modelName, withExtension: Self.modelExt) else {
            throw LlamaEngineError.modelUnavailable("找不到模型文件 \(Self.modelName).\(Self.modelExt)")
        }

        let mmprojPath = Bundle.main.url(forResource: Self.mmprojName, withExtension: Self.mmprojExt)?.path
        let created = try EmbeddedLlamaRuntime(
            modelPath: modelURL.path,
            mmprojPath: mmprojPath,
            contextLength: contextLength,
            onLoadProgress: makeProgressHandler(from: onLoadProgress)
        )
        runtime = created
        runtimeContextLength = contextLength
        return created
    }

    private func makeProgressHandler(
        from onLoadProgress: (@Sendable (Double) async -> Void)?
    ) -> (@Sendable (Double) -> Void)? {
        guard let onLoadProgress else { return nil }
        return { progress in
            Task {
                await onLoadProgress(progress)
            }
        }
    }

    private func resolveMaxTokens(
        requested: Int32,
        contextLength: Int32,
        profile: InferenceProfile,
        reasoningMode: ReasoningMode
    ) -> Int {
        if requested > 0 {
            return Int(requested)
        }

        if reasoningMode.isThinkingEnabled {
            // Let thinking mode use as much as possible; actual budget is capped by remaining context after prompt eval.
            return max(512, Int(contextLength) - 1)
        }

        let contextBased = max(64, min(Int(contextLength) / 2, 1024))
        switch profile {
        case .chat:
            return contextBased
        case .translation:
            return min(contextBased, 512)
        }
    }
}

private actor EmbeddedLlamaRuntime {
    private static let mediaMarker = "<__media__>"
    private static let legacyImageMarker = "<__image__>"
    private static let thinkingSuffix = "<think>\n"
    private static let noThinkingSuffix = "<think>\n\n</think>\n\n"

    private static let backendInitialized: Void = {
        llama_backend_init()
    }()

    private let model: OpaquePointer
    private let context: OpaquePointer
    private let vocab: OpaquePointer
    private let mtmdContext: OpaquePointer?
    private let contextLength: Int32
    private let batchSize: Int32
    private let supportsEnableThinking: Bool
    private let supportsVisionInput: Bool
    private let multimodalLoadError: String?

    init(
        modelPath: String,
        mmprojPath: String?,
        contextLength: Int32,
        onLoadProgress: (@Sendable (Double) -> Void)? = nil
    ) throws {
        _ = Self.backendInitialized

        var modelParams = llama_model_default_params()
        modelParams.n_gpu_layers = 99
        modelParams.use_mmap = true
        modelParams.use_mlock = false

        let progressRelay = onLoadProgress.map { handler in
            ModelLoadProgressRelay(handler: handler)
        }
        let progressUserData = progressRelay.map { Unmanaged.passRetained($0).toOpaque() }
        if let progressUserData {
            modelParams.progress_callback = { progress, userData in
                guard let userData else { return true }
                Unmanaged<ModelLoadProgressRelay>.fromOpaque(userData).takeUnretainedValue().report(progress)
                return true
            }
            modelParams.progress_callback_user_data = progressUserData
        }
        defer {
            if let progressUserData {
                Unmanaged<ModelLoadProgressRelay>.fromOpaque(progressUserData).release()
            }
        }

        guard let model = modelPath.withCString({ llama_model_load_from_file($0, modelParams) }) else {
            throw LlamaEngineError.modelUnavailable("加载模型失败：\(modelPath)")
        }
        onLoadProgress?(0.92)

        var ctxParams = llama_context_default_params()
        ctxParams.n_ctx = UInt32(max(1024, contextLength))
        ctxParams.n_batch = UInt32(max(32, min(contextLength, 512)))
        ctxParams.n_ubatch = UInt32(max(32, min(contextLength, 512)))
        let cpuCount = Int32(max(1, ProcessInfo.processInfo.activeProcessorCount))
        ctxParams.n_threads = max(1, cpuCount - 1)
        ctxParams.n_threads_batch = max(1, cpuCount - 1)
        ctxParams.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_AUTO

        guard let context = llama_init_from_model(model, ctxParams) else {
            llama_model_free(model)
            throw LlamaEngineError.modelUnavailable("创建推理上下文失败")
        }
        onLoadProgress?(0.96)

        guard let vocab = llama_model_get_vocab(model) else {
            llama_free(context)
            llama_model_free(model)
            throw LlamaEngineError.modelUnavailable("获取词表失败")
        }
        onLoadProgress?(0.97)

        self.model = model
        self.context = context
        self.vocab = vocab
        self.contextLength = Int32(ctxParams.n_ctx)
        self.batchSize = Int32(ctxParams.n_batch)

        if let tmpl = llama_model_chat_template(model, nil) {
            self.supportsEnableThinking = String(cString: tmpl).contains("enable_thinking")
        } else {
            self.supportsEnableThinking = false
        }

        let mtmdThreads = max(Int32(1), cpuCount - 1)
        if let mmprojPath {
            onLoadProgress?(0.98)
            var mtmdParams = mtmd_context_params_default()
            mtmdParams.use_gpu = true
            mtmdParams.print_timings = false
            mtmdParams.n_threads = mtmdThreads
            mtmdParams.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_AUTO
            mtmdParams.warmup = true

            if let loaded = mmprojPath.withCString({ mtmd_init_from_file($0, model, mtmdParams) }) {
                self.mtmdContext = loaded
                self.supportsVisionInput = mtmd_support_vision(loaded)
                self.multimodalLoadError = self.supportsVisionInput
                    ? nil
                    : "mmproj 已加载，但当前模型组合不支持图片输入"
            } else {
                self.mtmdContext = nil
                self.supportsVisionInput = false
                self.multimodalLoadError = "mmproj 初始化失败（可能与主模型不兼容）"
            }
        } else {
            self.mtmdContext = nil
            self.supportsVisionInput = false
            self.multimodalLoadError = "未找到 mmproj-BF16.gguf"
        }

        onLoadProgress?(1)
    }

    deinit {
        if let mtmdContext {
            mtmd_free(mtmdContext)
        }
        llama_free(context)
        llama_model_free(model)
    }

    func formatPrompt(
        messages: [PromptMessage],
        reasoningMode: ReasoningMode,
        profile: InferenceProfile
    ) throws -> String {
        let cStrings = messages.map { strdup($0.content) }
        defer { cStrings.forEach { free($0) } }

        var chatMessages = [llama_chat_message]()
        chatMessages.reserveCapacity(messages.count)
        for (idx, message) in messages.enumerated() {
            guard let cContent = cStrings[idx] else {
                throw LlamaEngineError.inferenceFailed("消息编码失败")
            }
            guard let cRole = strdup(message.role.rawValue) else {
                throw LlamaEngineError.inferenceFailed("角色编码失败")
            }
            chatMessages.append(llama_chat_message(role: cRole, content: cContent))
        }
        defer {
            for item in chatMessages {
                if let role = item.role {
                    free(UnsafeMutablePointer(mutating: role))
                }
            }
        }

        let required = chatMessages.withUnsafeMutableBufferPointer { buffer in
            llama_chat_apply_template(
                llama_model_chat_template(model, nil),
                buffer.baseAddress,
                buffer.count,
                true,
                nil,
                0
            )
        }

        guard required > 0 else {
            throw LlamaEngineError.inferenceFailed("chat template 格式化失败")
        }

        var out = [CChar](repeating: 0, count: Int(required) + 2)
        let written = chatMessages.withUnsafeMutableBufferPointer { buffer in
            llama_chat_apply_template(
                llama_model_chat_template(model, nil),
                buffer.baseAddress,
                buffer.count,
                true,
                &out,
                Int32(out.count)
            )
        }

        guard written > 0 else {
            throw LlamaEngineError.inferenceFailed("chat template 写入失败")
        }

        out[Int(written)] = 0
        let prompt = String(cString: out)
        return applyReasoningControl(to: prompt, reasoningMode: reasoningMode)
    }

    private func applyReasoningControl(
        to prompt: String,
        reasoningMode: ReasoningMode
    ) -> String {
        guard supportsEnableThinking else {
            return prompt
        }

        var controlled = prompt
        stripTrailingThinkingSuffix(from: &controlled)
        controlled = controlled.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"

        switch reasoningMode {
        case .thinking:
            controlled += Self.thinkingSuffix
        case .noThinking:
            controlled += Self.noThinkingSuffix
        }

        return controlled
    }

    private func stripTrailingThinkingSuffix(from prompt: inout String) {
        let candidates = [
            Self.noThinkingSuffix,
            "<think>\n\n</think>\n",
            "<think>\n\n</think>",
            Self.thinkingSuffix,
            "<think>"
        ]

        var stripped = true
        while stripped {
            stripped = false
            for suffix in candidates where prompt.hasSuffix(suffix) {
                prompt.removeLast(suffix.count)
                stripped = true
                break
            }
        }
    }

    func generate(
        prompt: String,
        imageDataList: [Data],
        maxTokens: Int,
        profile: InferenceProfile,
        generationConfig: GenerationConfig,
        onToken: (@Sendable (String) async -> Void)?
    ) async throws -> String {
        if Task.isCancelled {
            throw CancellationError()
        }

        let memory = llama_get_memory(context)
        llama_memory_clear(memory, true)
        let nPast: Int32
        if !imageDataList.isEmpty {
            nPast = try evaluatePromptMultimodal(prompt: prompt, imageDataList: imageDataList)
        } else {
            nPast = try evaluatePromptText(prompt: prompt)
        }

        let availableBudget = Int(max(0, contextLength - nPast - 1))
        let generationBudget = min(maxTokens, availableBudget)
        if generationBudget <= 0 {
            throw LlamaEngineError.inferenceFailed("上下文不足：请提高上下文长度或缩短输入")
        }

        let sampler = llama_sampler_chain_init(llama_sampler_chain_default_params())
        guard let sampler else {
            throw LlamaEngineError.inferenceFailed("采样器初始化失败")
        }
        defer { llama_sampler_free(sampler) }

        llama_sampler_chain_add(sampler, llama_sampler_init_top_k(generationConfig.topK))
        llama_sampler_chain_add(sampler, llama_sampler_init_top_p(generationConfig.topP, 1))
        llama_sampler_chain_add(sampler, llama_sampler_init_temp(generationConfig.temperature))
        llama_sampler_chain_add(sampler, llama_sampler_init_dist(UInt32(Date().timeIntervalSince1970)))

        var generated = ""
        var generationPos = nPast
        var pendingUTF8Bytes: [UInt8] = []

        for _ in 0..<generationBudget {
            if Task.isCancelled {
                throw CancellationError()
            }

            let next = llama_sampler_sample(sampler, context, -1)
            llama_sampler_accept(sampler, next)

            if llama_vocab_is_eog(vocab, next) {
                break
            }

            let pieceBytes = try tokenToPieceBytes(next)
            if !pieceBytes.isEmpty {
                pendingUTF8Bytes.append(contentsOf: pieceBytes)
                while let chunk = takeValidUTF8Chunk(from: &pendingUTF8Bytes) {
                    guard !chunk.isEmpty else { continue }
                    generated += chunk
                    if let onToken {
                        await onToken(chunk)
                    }
                }
            }

            try decode(tokens: [next], startingAt: generationPos)
            generationPos += 1
        }

        if !pendingUTF8Bytes.isEmpty {
            let tail = String(decoding: pendingUTF8Bytes, as: UTF8.self)
            if !tail.isEmpty {
                generated += tail
                if let onToken {
                    await onToken(tail)
                }
            }
        }

        return generated
    }

    private func evaluatePromptText(prompt: String) throws -> Int32 {
        let promptTokens = try tokenize(prompt)
        if promptTokens.isEmpty {
            throw LlamaEngineError.inferenceFailed("空提示词")
        }

        try decode(tokens: promptTokens, startingAt: 0)
        return Int32(promptTokens.count)
    }

    private func evaluatePromptMultimodal(prompt: String, imageDataList: [Data]) throws -> Int32 {
        guard let mtmdContext else {
            throw LlamaEngineError.multimodalUnavailable(multimodalUnavailableReason())
        }
        guard supportsVisionInput else {
            throw LlamaEngineError.multimodalUnavailable(multimodalUnavailableReason())
        }
        if imageDataList.isEmpty {
            throw LlamaEngineError.multimodalUnavailable("图片数据为空")
        }
        if !prompt.contains(Self.mediaMarker) && !prompt.contains(Self.legacyImageMarker) {
            throw LlamaEngineError.multimodalUnavailable("多模态提示词缺少媒体标记 \(Self.mediaMarker)")
        }

        var bitmaps: [OpaquePointer?] = []
        bitmaps.reserveCapacity(imageDataList.count)

        for imageData in imageDataList {
            if imageData.isEmpty {
                throw LlamaEngineError.multimodalUnavailable("图片数据为空")
            }

            let bitmap = imageData.withUnsafeBytes { rawBuffer -> OpaquePointer? in
                guard let base = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                    return nil
                }
                return mtmd_helper_bitmap_init_from_buf(mtmdContext, base, rawBuffer.count)
            }

            guard let bitmap else {
                throw LlamaEngineError.multimodalUnavailable("图片预处理失败：不支持的图片格式或数据损坏")
            }
            bitmaps.append(bitmap)
        }
        defer {
            for case let bitmap? in bitmaps {
                mtmd_bitmap_free(bitmap)
            }
        }

        guard let chunks = mtmd_input_chunks_init() else {
            throw LlamaEngineError.multimodalUnavailable("创建多模态输入分块失败")
        }
        defer { mtmd_input_chunks_free(chunks) }

        let tokenizeResult: Int32 = prompt.withCString { cPrompt in
            var inputText = mtmd_input_text(
                text: cPrompt,
                add_special: false,
                parse_special: true
            )
            return bitmaps.withUnsafeMutableBufferPointer { bitmapBuffer in
                withUnsafePointer(to: &inputText) { inputTextPointer in
                    mtmd_tokenize(
                        mtmdContext,
                        chunks,
                        inputTextPointer,
                        bitmapBuffer.baseAddress,
                        bitmapBuffer.count
                    )
                }
            }
        }

        if tokenizeResult != 0 {
            switch tokenizeResult {
            case 1:
                throw LlamaEngineError.multimodalUnavailable("图片数量与提示词中的媒体标记数量不匹配")
            case 2:
                throw LlamaEngineError.multimodalUnavailable("图片编码失败，mmproj 无法处理该输入")
            default:
                throw LlamaEngineError.multimodalUnavailable("多模态 tokenization 失败（code=\(tokenizeResult)）")
            }
        }

        var newNPast: Int32 = 0
        let evalResult = mtmd_helper_eval_chunks(
            mtmdContext,
            context,
            chunks,
            0,
            0,
            batchSize,
            true,
            &newNPast
        )
        if evalResult != 0 {
            throw LlamaEngineError.multimodalUnavailable("多模态提示词评估失败（code=\(evalResult)）")
        }

        return newNPast
    }

    private func multimodalUnavailableReason() -> String {
        multimodalLoadError ?? "当前模型未启用多模态能力"
    }

    private func tokenize(_ text: String) throws -> [llama_token] {
        var tokens = [llama_token](repeating: 0, count: max(32, text.utf8.count + 8))

        let nTokensInitial = text.withCString { cText in
            llama_tokenize(
                vocab,
                cText,
                Int32(strlen(cText)),
                &tokens,
                Int32(tokens.count),
                false,
                true
            )
        }

        var nTokens = nTokensInitial
        if nTokens < 0 {
            let required = Int(-nTokens)
            tokens = [llama_token](repeating: 0, count: required + 8)
            nTokens = text.withCString { cText in
                llama_tokenize(
                    vocab,
                    cText,
                    Int32(strlen(cText)),
                    &tokens,
                    Int32(tokens.count),
                    false,
                    true
                )
            }
        }

        guard nTokens >= 0 else {
            throw LlamaEngineError.inferenceFailed("tokenize 失败")
        }

        return Array(tokens.prefix(Int(nTokens)))
    }

    private func decode(tokens: [llama_token], startingAt posStart: Int32) throws {
        var batch = llama_batch_init(batchSize, 0, 1)
        defer { llama_batch_free(batch) }

        var offset = 0
        while offset < tokens.count {
            let n = min(Int(batchSize), tokens.count - offset)
            batch.n_tokens = Int32(n)

            for i in 0..<n {
                batch.token[i] = tokens[offset + i]
                batch.pos[i] = posStart + Int32(offset + i)
                batch.n_seq_id[i] = 1
                batch.seq_id[i]?[0] = 0
                batch.logits[i] = (i == n - 1) ? 1 : 0
            }

            let rc = llama_decode(context, batch)
            if rc != 0 {
                throw LlamaEngineError.inferenceFailed("decode 失败（code=\(rc)）")
            }

            offset += n
        }
    }

    private func tokenToPieceBytes(_ token: llama_token) throws -> [UInt8] {
        var buffer = [CChar](repeating: 0, count: 64)

        var n = llama_token_to_piece(
            vocab,
            token,
            &buffer,
            Int32(buffer.count),
            0,
            false
        )

        if n < 0 {
            buffer = [CChar](repeating: 0, count: Int(-n) + 8)
            n = llama_token_to_piece(
                vocab,
                token,
                &buffer,
                Int32(buffer.count),
                0,
                false
            )
        }

        guard n >= 0 else {
            throw LlamaEngineError.inferenceFailed("token_to_piece 失败")
        }

        return buffer.withUnsafeBufferPointer { raw in
            let ptr = UnsafeRawPointer(raw.baseAddress!).assumingMemoryBound(to: UInt8.self)
            return Array(UnsafeBufferPointer(start: ptr, count: Int(n)))
        }
    }

    private func takeValidUTF8Chunk(from bytes: inout [UInt8]) -> String? {
        guard !bytes.isEmpty else { return nil }

        for prefixLength in stride(from: bytes.count, through: 1, by: -1) {
            if let decoded = String(bytes: bytes[0..<prefixLength], encoding: .utf8) {
                bytes.removeFirst(prefixLength)
                return decoded
            }
        }

        // Avoid getting stuck forever on malformed byte sequences.
        if bytes.count >= 8 {
            bytes.removeFirst()
            return "�"
        }
        return nil
    }
}
