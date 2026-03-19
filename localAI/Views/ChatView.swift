import SwiftUI
import PhotosUI
import UIKit
import ImageIO

struct ChatView: View {
    private static let bottomAnchorID = "bottom-anchor"
    private static let sidebarWidth: CGFloat = 304
    private static let maxAttachmentPixelSize = 1344
    private static let attachmentJPEGQuality: CGFloat = 0.82
    private static let autoScrollInterval: TimeInterval = 1.0 / 8.0
    private static let streamingMessageID = UUID()
    private static let streamingMessageTimestamp = Date.distantPast

    private struct GalleryPresentation: Identifiable {
        let id = UUID()
        let items: [GalleryImageItem]
        let initialIndex: Int
        let title: String
    }

    @StateObject private var viewModel = ChatViewModel()
    @EnvironmentObject private var localization: LocalizationManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(ChatTitleMode.storageKey) private var titleModeRawValue = ChatTitleMode.content.rawValue
    @AppStorage(ChatStyle.storageKey) private var chatStyleRawValue = ChatStyle.defaultStyle.rawValue
    @AppStorage("thinking_mode_unlocked") private var thinkingModeUnlocked = false

    @State private var pickedImageItems: [PhotosPickerItem] = []
    @State private var selectedImageDataList: [Data] = []
    @State private var showSidebar = false
    @State private var sidebarDragTranslation: CGFloat = 0
    @State private var isEdgeDraggingSidebar = false
    @State private var showSettings = false
    @State private var renamingConversationID: UUID?
    @State private var renamingTitleText = ""
    @State private var showModuleDialog = false
    @State private var showImplicitModuleLoadingDialog = false
    @State private var moduleProgressValue: Double = 0
    @State private var moduleLoadDismissWorkItem: DispatchWorkItem?
    @State private var activeGallery: GalleryPresentation?
    @State private var scrollViewRef: UIScrollView?
    @State private var lastAutoScrollAt: TimeInterval = 0
    @State private var suppressAutoScrollUntilNextUserMessage = false
    @State private var showCustomContextWarning = false
    @State private var showCustomContextLengthDialog = false
    @State private var customContextLengthInput = ""
    @State private var showImagePickerWarning = false
    @State private var showThinkingLockedHint = false

    private static let historyDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd"
        return formatter
    }()

    private static let historyTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    var body: some View {
        ZStack {
            AppTheme.backgroundGradient
                .ignoresSafeArea()

            if shouldShowConversationBackdropLogo {
                PocketAILogoBackdrop()
                    .transition(.opacity)
            }

            chatContent

            sidebarOverlay

            moduleDialogOverlay

            implicitModuleLoadingOverlay

            edgeDragActivationLayer
        }
        .navigationDestination(isPresented: $showSettings) {
            SettingsView()
        }
        .animation(.easeOut(duration: 0.24), value: shouldShowConversationBackdropLogo)
        .fullScreenCover(item: $activeGallery) { gallery in
            ImageGalleryViewer(
                items: gallery.items,
                initialIndex: gallery.initialIndex,
                title: gallery.title
            )
        }
        .alert(localization.text(.renameTitle), isPresented: isRenameAlertPresented) {
            TextField(localization.text(.renamePlaceholder), text: $renamingTitleText)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
            Button(localization.text(.commonCancel), role: .cancel) {
                clearRenamingState()
            }
            Button(localization.text(.commonSave)) {
                applyCustomTitle()
            }
        } message: {
            Text(localization.text(.renameMessage))
        }
        .alert(localization.text(.contextLengthCustom), isPresented: $showCustomContextWarning) {
            Button(localization.text(.commonCancel), role: .cancel) {
                customContextLengthInput = ""
            }
            Button(localization.text(.contextLengthCustomWarningConfirm)) {
                showCustomContextLengthDialog = true
            }
        } message: {
            Text(localization.text(.contextLengthCustomWarning))
        }
        .alert(localization.text(.contextLengthCustom), isPresented: $showCustomContextLengthDialog) {
            TextField(localization.text(.contextLengthCustomPlaceholder), text: $customContextLengthInput)
                .keyboardType(.numberPad)
            Button(localization.text(.commonCancel), role: .cancel) {
                customContextLengthInput = ""
            }
            Button(localization.text(.commonSave)) {
                applyCustomContextLength()
            }
        } message: {
            Text(localization.text(.contextLengthCustomMessage))
        }
        .alert(localization.text(.attachmentPickImage), isPresented: $showImagePickerWarning) {
            Button(localization.text(.commonCancel), role: .cancel) {
                clearSelectedImages()
            }
            Button(localization.text(.attachmentImageWarningConfirm)) {
                // Images already loaded, just dismiss
            }
        } message: {
            Text(localization.text(.attachmentImageWarning))
        }
        .alert(localization.text(.settingsThinkingMode), isPresented: $showThinkingLockedHint) {
            Button(localization.text(.commonCancel), role: .cancel) { }
        } message: {
            Text(localization.text(.thinkingModeLockedHint))
        }
        .onAppear {
            viewModel.updateTitleMode(rawValue: titleModeRawValue)
            viewModel.updateChatStyle(rawValue: chatStyleRawValue)
            moduleProgressValue = viewModel.moduleLoadProgress
        }
        .onChange(of: titleModeRawValue) {
            viewModel.updateTitleMode(rawValue: titleModeRawValue)
        }
        .onChange(of: chatStyleRawValue) {
            viewModel.updateChatStyle(rawValue: chatStyleRawValue)
        }
        .onChange(of: scenePhase) {
            viewModel.handleScenePhaseChange(scenePhase)
        }
        .onChange(of: viewModel.moduleStatus) {
            handleModuleStatusChanged(viewModel.moduleStatus)
        }
        .onChange(of: viewModel.moduleLoadProgress) {
            syncModuleProgressFromBackend(viewModel.moduleLoadProgress)
        }
        .onChange(of: showModuleDialog) {
            if showModuleDialog {
                moduleLoadDismissWorkItem?.cancel()
                showImplicitModuleLoadingDialog = false
                moduleProgressValue = viewModel.moduleLoadProgress
            }
        }
        .onChange(of: localization.currentLanguage) {
            viewModel.refreshLocalizedHistoryItems()
        }
        .onChange(of: thinkingModeUnlocked) {
            viewModel.setThinkingModeUnlocked(thinkingModeUnlocked)
        }
    }

    private var activeInputTextBinding: Binding<String> {
        Binding(
            get: { viewModel.draft() },
            set: { viewModel.updateDraft($0) }
        )
    }

    private var activeInputText: String {
        viewModel.draft()
    }

    private var composerPlaceholder: String {
        localization.text(.composerPlaceholder)
    }

    private var composerHasAttachment: Bool {
        !selectedImageDataList.isEmpty
    }

    private var shouldShowConversationBackdropLogo: Bool {
        viewModel.messages.isEmpty && !viewModel.isGenerating
    }

    private var isRenameAlertPresented: Binding<Bool> {
        Binding(
            get: { renamingConversationID != nil },
            set: { isPresented in
                if !isPresented {
                    clearRenamingState()
                }
            }
        )
    }

    // MARK: - Chat Content

    private var chatContent: some View {
        VStack(spacing: 0) {
            headerBar

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.messages) { message in
                            MessageBubble(
                                message: message,
                                usesMarkdown: message.role == .assistant,
                                isThinkingExpanded: viewModel.isThinkingExpanded(for: message.id, isStreaming: false),
                                canToggleThinking: viewModel.canToggleThinkingDetails
                            ) {
                                viewModel.toggleThinkingExpansion(for: message.id, isStreaming: false)
                            } onOpenImageAtIndex: { imageIndex in
                                openConversationGallery(from: message, imageIndex: imageIndex)
                            }
                                .equatable()
                                .id(message.id)
                        }

                        if viewModel.isGenerating {
                            MessageBubble(
                                message: Message(
                                    id: Self.streamingMessageID,
                                    role: .assistant,
                                    content: viewModel.currentStreamingText,
                                    thinking: viewModel.currentStreamingThinking.isEmpty ? nil : viewModel.currentStreamingThinking,
                                    timestamp: Self.streamingMessageTimestamp
                                ),
                                isStreaming: true,
                                isImageProcessingPlaceholder: viewModel.showsImageProcessingPlaceholder,
                                usesMarkdown: false,
                                isThinkingExpanded: viewModel.isThinkingExpanded(for: Self.streamingMessageID, isStreaming: true),
                                canToggleThinking: viewModel.canToggleThinkingDetails
                            ) {
                                viewModel.toggleThinkingExpansion(for: Self.streamingMessageID, isStreaming: true)
                            }
                            .id("streaming")
                        }

                        Color.clear
                            .frame(height: 1)
                            .id(Self.bottomAnchorID)
                    }
                    .padding(.horizontal, AppTheme.contentPadding)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                    .background {
                        ScrollViewFinder { sv in
                            scrollViewRef = sv
                        }
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .simultaneousGesture(TapGesture().onEnded {
                    dismissKeyboard()
                })
                .onChange(of: viewModel.currentStreamingText) {
                    autoScrollIfAppropriate(proxy)
                }
                .onChange(of: viewModel.currentStreamingThinking) {
                    autoScrollIfAppropriate(proxy)
                }
                .onChange(of: viewModel.messages.count) {
                    onMessagesCountChanged(proxy)
                }
            }

            attachmentBar

            InputBar(
                text: activeInputTextBinding,
                placeholder: composerPlaceholder,
                isGenerating: viewModel.isGenerating,
                hasAttachment: composerHasAttachment
            ) {
                sendMessage()
            } onStop: {
                armAutoScrollSuppressionForStopIfNeeded()
                viewModel.stop()
            }
            .id(viewModel.mode)
        }
        .onChange(of: pickedImageItems) {
            Task {
                let wasEmpty = selectedImageDataList.isEmpty
                await loadSelectedImages()
                if wasEmpty && !selectedImageDataList.isEmpty {
                    showImagePickerWarning = true
                }
            }
        }
        .onChange(of: hasImageSelection) {
            applyAttachmentReasoningLockIfNeeded()
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 12) {
            // 侧栏按钮（最左）
            Button {
                dismissKeyboard()
                setSidebar(open: true)
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.title3)
                    .foregroundStyle(AppTheme.primaryText)
            }

            // 模型名称
            Text("Qwen3.5-2B")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.primaryText)

            // 状态指示器
            Button {
                moduleLoadDismissWorkItem?.cancel()
                showImplicitModuleLoadingDialog = false
                showModuleDialog = true
            } label: {
                HStack(spacing: 5) {
                    Circle()
                        .fill(moduleStatusColor)
                        .frame(width: 7, height: 7)
                    Text(moduleStatusText)
                        .font(.caption)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background {
                    Capsule()
                        .fill(.ultraThinMaterial)
                }
                .foregroundStyle(AppTheme.primaryText)
            }
            .buttonStyle(.plain)

            Spacer()

            // 上下文长度菜单
            Menu {
                Section(localization.text(.contextLengthTitle)) {
                    ForEach(ContextLength.presets) { length in
                        Button {
                            viewModel.changeContextLength(to: length)
                        } label: {
                            HStack {
                                Text("\(length.displayLabel) · \(contextLengthDescription(length))")
                                if length == viewModel.contextLength {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }

                    Divider()

                    Button {
                        if case .custom(let value) = viewModel.contextLength {
                            customContextLengthInput = "\(value)"
                        } else {
                            customContextLengthInput = ""
                        }
                        showCustomContextWarning = true
                    } label: {
                        HStack {
                            Text(localization.text(.contextLengthCustom))
                            if !viewModel.contextLength.isPreset {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "text.alignleft")
                    Text(viewModel.contextLength.displayLabel)
                }
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background {
                    Capsule()
                        .fill(.ultraThinMaterial)
                }
                .foregroundStyle(AppTheme.primaryText)
            }

            // 新会话
            Button {
                viewModel.startNewConversation()
            } label: {
                Image(systemName: "plus.bubble")
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .padding(.horizontal, AppTheme.contentPadding)
        .padding(.vertical, 14)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea(edges: .top)
        }
    }

    // MARK: - Left Sidebar Overlay

    private var sidebarOverlay: some View {
        let progress = sidebarPresentationProgress

        return ZStack(alignment: .leading) {
            Color.black.opacity(sidebarBackdropOpacity)
                .ignoresSafeArea()
                .allowsHitTesting(progress > 0.001)
                .onTapGesture {
                    setSidebar(open: false)
                }

            sidebarContent
                .frame(width: Self.sidebarWidth)
                .frame(maxHeight: .infinity)
                .background {
                    sidebarPanelBackground
                        .ignoresSafeArea()
                }
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.12))
                        .frame(width: 0.7)
                }
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.38 : 0.16), radius: 20, x: 10, y: 0)
                .offset(x: sidebarOffsetX)
                .allowsHitTesting(progress > 0.001)
                .simultaneousGesture(sidebarCloseDragGesture)
        }
        .opacity(progress > 0.001 ? 1 : 0)
    }

    private var sidebarContent: some View {
        VStack(spacing: 12) {
            // 顶部标题栏
            HStack {
                Text(localization.text(.sidebarHistory))
                    .font(.headline)
                    .foregroundStyle(AppTheme.primaryText)
                Spacer()
                Button {
                    viewModel.startNewConversation()
                    setSidebar(open: false)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.pencil")
                        Text(localization.text(.sidebarNewConversation))
                    }
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.primaryText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                            .overlay {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.white.opacity(0.15), lineWidth: 0.8)
                            }
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            // 会话列表
            if viewModel.historyItems.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 32))
                        .foregroundStyle(AppTheme.secondaryText)
                    Text(emptyHistoryText)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(viewModel.historyItems) { item in
                        historyConversationRow(
                            item: item,
                            isCurrent: viewModel.isCurrentConversation(item.id)
                        )
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 24))
                        .listRowSeparator(.visible)
                        .listRowBackground(
                            (viewModel.isCurrentConversation(item.id) ? AppTheme.accent.opacity(0.07) : Color.clear)
                        )
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .frame(maxHeight: .infinity)
            }

            settingsEntryButton
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
    }

    private var sidebarPanelBackground: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
            LinearGradient(
                colors: [
                    colorScheme == .dark ? Color.white.opacity(0.30) : Color.white.opacity(0.62),
                    colorScheme == .dark ? Color.white.opacity(0.12) : Color.white.opacity(0.24)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            LinearGradient(
                colors: [
                    colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.18),
                    colorScheme == .dark ? Color.black.opacity(0.08) : Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Rectangle()
                .fill(colorScheme == .dark ? Color.white.opacity(0.04) : Color.white.opacity(0.16))
        }
    }

    // MARK: - Center Module Dialog Overlay

    private var moduleDialogOverlay: some View {
        ZStack {
            if showModuleDialog {
                // 半透明遮罩
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            showModuleDialog = false
                        }
                    }
                    .transition(.opacity)

                // 居中卡片
                VStack(spacing: 16) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(moduleStatusColor)
                            .frame(width: 10, height: 10)
                        Text(moduleStatusText)
                            .font(.headline)
                            .foregroundStyle(AppTheme.primaryText)
                    }

                    ProgressView(value: moduleProgressValue, total: 1)
                        .progressViewStyle(.linear)

                    HStack(spacing: 12) {
                        Button(localization.text(.moduleLoad)) {
                            moduleProgressValue = 0
                            viewModel.preloadEngine()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.moduleStatus == .loading || viewModel.moduleStatus == .loaded)

                        Button(localization.text(.moduleUnload)) {
                            animateModuleUnloadReset()
                            viewModel.unloadEngine()
                        }
                        .buttonStyle(.bordered)
                        .disabled(viewModel.moduleStatus == .notLoaded || viewModel.moduleStatus == .loading)
                    }
                }
                .padding(26)
                .frame(width: 320)
                .background {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                        }
                }
                .shadow(color: .black.opacity(0.3), radius: 20)
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showModuleDialog)
    }

    private var implicitModuleLoadingOverlay: some View {
        ZStack {
            if showImplicitModuleLoadingDialog && !showModuleDialog {
                Color.black.opacity(0.2)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)

                VStack(alignment: .leading, spacing: 12) {
                    Text(localization.text(.moduleLoadingOverlay))
                        .font(.headline)
                        .foregroundStyle(AppTheme.primaryText)

                    ProgressView(value: moduleProgressValue, total: 1)
                        .progressViewStyle(.linear)
                }
                .padding(18)
                .frame(width: 240)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                        }
                }
                .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
                .transition(.scale(scale: 0.96).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.18), value: showImplicitModuleLoadingDialog)
    }

    // MARK: - Actions

    private func sendMessage() {
        let text = activeInputText
        let shouldShowImplicitDialog = shouldShowImplicitLoadingDialogForSend
        guard viewModel.send(text, imageDataList: selectedImageDataList) else { return }
        if shouldShowImplicitDialog {
            moduleLoadDismissWorkItem?.cancel()
            moduleProgressValue = viewModel.moduleLoadProgress
            showImplicitModuleLoadingDialog = true
            if viewModel.moduleStatus == .loaded || viewModel.moduleLoadProgress >= 1 {
                scheduleImplicitLoadingDismiss(after: 0.05)
            }
        }
        clearSelectedImages()
    }

    private func clearSelectedImages() {
        selectedImageDataList = []
        pickedImageItems = []
    }

    private func removeSelectedImage(at index: Int) {
        guard selectedImageDataList.indices.contains(index) else { return }
        selectedImageDataList.remove(at: index)
        if pickedImageItems.indices.contains(index) {
            pickedImageItems.remove(at: index)
        }
    }

    private func loadSelectedImages() async {
        let limitedItems = Array(pickedImageItems.prefix(ChatViewModel.maxImageAttachmentCount))
        if limitedItems.count != pickedImageItems.count {
            await MainActor.run {
                pickedImageItems = limitedItems
            }
        }

        guard !limitedItems.isEmpty else {
            await MainActor.run {
                selectedImageDataList = []
            }
            return
        }

        var loadedImages: [Data] = []
        loadedImages.reserveCapacity(limitedItems.count)

        for item in limitedItems {
            guard let rawData = try? await item.loadTransferable(type: Data.self),
                  let preparedData = prepareAttachmentData(from: rawData) else {
                continue
            }
            loadedImages.append(preparedData)
        }

        await MainActor.run {
            selectedImageDataList = loadedImages
        }
    }
    private func prepareAttachmentData(from rawData: Data) -> Data? {
        let downsampleOptions: CFDictionary = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCache: false,
            kCGImageSourceThumbnailMaxPixelSize: Self.maxAttachmentPixelSize
        ] as CFDictionary

        if let source = CGImageSourceCreateWithData(rawData as CFData, nil),
           let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions) {
            let image = UIImage(cgImage: cgImage)
            if let jpegData = image.jpegData(compressionQuality: Self.attachmentJPEGQuality) {
                return jpegData
            }
            if let pngData = image.pngData() {
                return pngData
            }
        }

        guard let image = UIImage(data: rawData) else { return nil }
        return image.jpegData(compressionQuality: Self.attachmentJPEGQuality) ?? image.pngData()
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    /// 直接读取 UIScrollView 实时状态，判断是否应该自动滚动。
    private func autoScrollIfAppropriate(_ proxy: ScrollViewProxy) {
        guard viewModel.shouldAutoScroll else { return }
        guard !suppressAutoScrollUntilNextUserMessage else { return }
        let now = Date().timeIntervalSinceReferenceDate
        guard now - lastAutoScrollAt >= Self.autoScrollInterval else { return }
        guard let sv = scrollViewRef else { return }
        guard !sv.isDragging, !sv.isDecelerating else { return }
        guard isNearBottom(sv) else { return }
        lastAutoScrollAt = now
        proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
    }

    /// 消息数量变化：用户发了新消息 → 无条件滚到底部；AI 回复完成 → 尊重当前位置
    private func onMessagesCountChanged(_ proxy: ScrollViewProxy) {
        if let last = viewModel.messages.last, last.role == .user {
            suppressAutoScrollUntilNextUserMessage = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
                }
            }
        } else {
            autoScrollIfAppropriate(proxy)
        }
    }

    private func armAutoScrollSuppressionForStopIfNeeded() {
        guard let sv = scrollViewRef else { return }
        suppressAutoScrollUntilNextUserMessage = !isNearBottom(sv)
    }

    private func isNearBottom(_ scrollView: UIScrollView, threshold: CGFloat = 80) -> Bool {
        let bottomInset = scrollView.adjustedContentInset.bottom
        let bottomOfViewport = scrollView.contentOffset.y + scrollView.bounds.height - bottomInset
        let contentBottom = scrollView.contentSize.height
        return contentBottom - bottomOfViewport < threshold
    }

    // MARK: - Helpers

    private func contextLengthDescription(_ length: ContextLength) -> String {
        if let key = length.descriptionKey {
            return localization.text(key)
        }
        return ""
    }

    private var emptyHistoryText: String {
        localization.text(.sidebarEmptyHistory)
    }

    private var attachmentBar: some View {
        let isReasoningLockedByAttachment = hasImageSelection
        let isReasoningLocked = isReasoningLockedByAttachment || !viewModel.isThinkingModeUnlocked
        let displayedReasoningMode: ReasoningMode = isReasoningLocked ? .noThinking : viewModel.reasoningMode
        let reasoningModeText = localization.text(displayedReasoningMode.titleKey)
        let pickImageText = localization.text(.attachmentPickImage)

        return HStack(spacing: 10) {
            Button {
                if isReasoningLockedByAttachment {
                    return
                }
                if !viewModel.isThinkingModeUnlocked {
                    showThinkingLockedHint = true
                    return
                }
                viewModel.toggleReasoningMode()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: displayedReasoningMode.iconName)
                    Text(reasoningModeText)
                }
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background {
                    Capsule()
                        .fill(reasoningControlFill(
                            isActive: displayedReasoningMode.isThinkingEnabled,
                            isLocked: isReasoningLocked
                        ))
                }
                .overlay {
                    Capsule()
                        .stroke(reasoningControlStroke(
                            isActive: displayedReasoningMode.isThinkingEnabled,
                            isLocked: isReasoningLocked
                        ), lineWidth: 0.8)
                }
                .foregroundStyle(reasoningControlForeground(
                    isActive: displayedReasoningMode.isThinkingEnabled,
                    isLocked: isReasoningLocked
                ))
            }
            .buttonStyle(.plain)

            PhotosPicker(
                selection: $pickedImageItems,
                maxSelectionCount: ChatViewModel.maxImageAttachmentCount,
                matching: .images
            ) {
                HStack(spacing: 6) {
                    Image(systemName: hasImageSelection ? "photo.fill.on.rectangle.fill" : "photo.on.rectangle.angled")
                    Text(pickImageText)
                }
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background {
                    Capsule()
                        .fill(controlFill(isActive: hasImageSelection))
                }
                .overlay {
                    Capsule()
                        .stroke(controlStroke(isActive: hasImageSelection), lineWidth: 0.8)
                }
            }
            .tint(hasImageSelection ? AppTheme.accent : AppTheme.primaryText)

            if !selectedImageDataList.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(selectedImageDataList.enumerated()), id: \.offset) { index, data in
                            if let previewImage = UIImage(data: data) {
                                ZStack(alignment: .topTrailing) {
                                    Button {
                                        openComposerGallery(at: index)
                                    } label: {
                                        Image(uiImage: previewImage)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 42, height: 42)
                                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    }
                                    .buttonStyle(.plain)

                                    Button {
                                        removeSelectedImage(at: index)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 16))
                                            .foregroundStyle(.white, Color.black.opacity(0.45))
                                            .background(Color.black.opacity(0.001), in: Circle())
                                    }
                                    .offset(x: 4, y: -4)
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, AppTheme.contentPadding)
        .padding(.vertical, 6)
    }

    private func controlFill(isActive: Bool) -> Color {
        if isActive {
            return AppTheme.accent.opacity(0.22)
        }
        return colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05)
    }

    private func controlStroke(isActive: Bool) -> Color {
        if isActive {
            return AppTheme.accent.opacity(0.58)
        }
        return colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.14)
    }

    private func reasoningControlFill(isActive: Bool, isLocked: Bool) -> Color {
        if isLocked {
            return Color.yellow.opacity(colorScheme == .dark ? 0.32 : 0.24)
        }
        if isActive {
            return Color.blue.opacity(colorScheme == .dark ? 0.32 : 0.22)
        }
        return Color.green.opacity(colorScheme == .dark ? 0.28 : 0.18)
    }

    private func reasoningControlStroke(isActive: Bool, isLocked: Bool) -> Color {
        if isLocked {
            return Color.yellow.opacity(0.86)
        }
        if isActive {
            return Color.blue.opacity(0.72)
        }
        return Color.green.opacity(0.72)
    }

    private func reasoningControlForeground(isActive: Bool, isLocked: Bool) -> Color {
        if isLocked {
            return colorScheme == .dark ? Color.yellow : Color.orange
        }
        if isActive {
            return colorScheme == .dark ? Color(red: 0.55, green: 0.72, blue: 1.0) : Color.blue
        }
        return colorScheme == .dark ? Color.green : Color(red: 0.15, green: 0.55, blue: 0.25)
    }

    private var hasImageSelection: Bool {
        !selectedImageDataList.isEmpty || !pickedImageItems.isEmpty
    }

    private func applyAttachmentReasoningLockIfNeeded() {
        guard hasImageSelection else { return }
        viewModel.updateReasoningMode(.noThinking)
    }

    private var shouldShowImplicitLoadingDialogForSend: Bool {
        guard !showModuleDialog else { return false }
        switch viewModel.moduleStatus {
        case .notLoaded, .failed:
            return true
        case .loading, .loaded:
            return false
        }
    }

    private func syncModuleProgressFromBackend(_ progress: Double) {
        let clamped = min(max(progress, 0), 1)
        guard viewModel.moduleStatus == .loading || viewModel.moduleStatus == .loaded else { return }
        withAnimation(.linear(duration: 0.08)) {
            moduleProgressValue = clamped
        }
        if clamped >= 1 {
            scheduleImplicitLoadingDismiss(after: 0.08)
        }
    }

    private func animateModuleUnloadReset() {
        withAnimation(.easeOut(duration: 0.04)) {
            moduleProgressValue = 0
        }
    }

    private func handleModuleStatusChanged(_ status: EngineModuleStatus) {
        switch status {
        case .loading:
            moduleLoadDismissWorkItem?.cancel()
        case .loaded:
            withAnimation(.easeOut(duration: 0.1)) {
                moduleProgressValue = 1
            }
            scheduleImplicitLoadingDismiss(after: 0.2)
        case .failed:
            withAnimation(.easeOut(duration: 0.08)) {
                moduleProgressValue = 0
            }
            scheduleImplicitLoadingDismiss(after: 0.05)
        case .notLoaded:
            animateModuleUnloadReset()
            scheduleImplicitLoadingDismiss(after: 0.05)
        }
    }

    private func scheduleImplicitLoadingDismiss(after delay: TimeInterval) {
        moduleLoadDismissWorkItem?.cancel()
        guard showImplicitModuleLoadingDialog else { return }

        let work = DispatchWorkItem {
            withAnimation(.easeOut(duration: 0.16)) {
                showImplicitModuleLoadingDialog = false
            }
        }
        moduleLoadDismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, delay), execute: work)
    }

    private var moduleStatusColor: Color {
        switch viewModel.moduleStatus {
        case .notLoaded:
            return .orange
        case .loading:
            return .yellow
        case .loaded:
            return .green
        case .failed:
            return .red
        }
    }

    private var moduleStatusText: String {
        localization.text(viewModel.moduleStatus.titleKey)
    }

    private var sidebarPresentationProgress: CGFloat {
        let base: CGFloat = showSidebar ? 1 : 0
        let progress = base + (sidebarDragTranslation / Self.sidebarWidth)
        return min(max(progress, 0), 1)
    }

    private var sidebarOffsetX: CGFloat {
        -Self.sidebarWidth * (1 - sidebarPresentationProgress)
    }

    private var sidebarBackdropOpacity: Double {
        let baseOpacity = colorScheme == .dark ? 0.22 : 0.12
        return Double(baseOpacity * sidebarPresentationProgress)
    }

    private var edgeDragActivationLayer: some View {
        Color.clear
            .frame(width: 24)
            .contentShape(Rectangle())
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .ignoresSafeArea()
            .allowsHitTesting(!showSidebar)
            .highPriorityGesture(edgeSidebarOpenDragGesture)
    }

    private var edgeSidebarOpenDragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                guard !showSidebar else { return }

                if !isEdgeDraggingSidebar {
                    guard value.startLocation.x <= 22 else { return }
                    isEdgeDraggingSidebar = true
                }

                let horizontalTranslation = max(0, value.translation.width)
                sidebarDragTranslation = min(Self.sidebarWidth, horizontalTranslation)
            }
            .onEnded { value in
                guard isEdgeDraggingSidebar else { return }
                isEdgeDraggingSidebar = false

                let projected = max(value.translation.width, value.predictedEndTranslation.width)
                let shouldOpen = projected > (Self.sidebarWidth * 0.32)
                setSidebar(open: shouldOpen)
            }
    }

    private var sidebarCloseDragGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .global)
            .onChanged { value in
                guard showSidebar else { return }
                guard abs(value.translation.width) > abs(value.translation.height) else { return }

                if value.translation.width < 0 {
                    sidebarDragTranslation = max(-Self.sidebarWidth, value.translation.width)
                } else {
                    // 右拖提供轻微阻尼回弹，避免抽屉抖动。
                    sidebarDragTranslation = min(18, value.translation.width * 0.25)
                }
            }
            .onEnded { value in
                guard showSidebar else { return }
                guard abs(value.translation.width) > abs(value.translation.height) else {
                    sidebarDragTranslation = 0
                    return
                }

                let projected = min(value.translation.width, value.predictedEndTranslation.width)
                let shouldClose = projected < (-Self.sidebarWidth * 0.25)
                setSidebar(open: !shouldClose)
            }
    }

    private var settingsEntryButton: some View {
        Button {
            openSettingsPage()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "gearshape")
                    .font(.system(size: 15, weight: .semibold))
                Text(localization.text(.sidebarSettings))
                    .font(.subheadline.weight(.medium))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.secondaryText)
            }
            .foregroundStyle(AppTheme.primaryText)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.05))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(
                                colorScheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.14),
                                lineWidth: 0.8
                            )
                    }
            }
        }
        .buttonStyle(.plain)
    }

    private func historyConversationRow(item: ConversationHistoryItem, isCurrent: Bool) -> some View {
        Button {
            clearRenamingState()
            viewModel.loadConversation(id: item.id)
            setSidebar(open: false)
        } label: {
            historyConversationRowContent(item: item, isCurrent: isCurrent)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu(menuItems: {
            Button(localization.text(.historyCustomTitle), systemImage: "pencil") {
                beginCustomTitleEdit(for: item)
            }

            Button(
                viewModel.isGeneratingTitle(for: item.id)
                    ? localization.text(.historyAITitleGenerating)
                    : localization.text(.historyAITitleGenerate),
                systemImage: viewModel.isGeneratingTitle(for: item.id) ? "hourglass" : "wand.and.stars"
            ) {
                requestAITitle(for: item)
            }
            .disabled(viewModel.isGeneratingTitle(for: item.id))

            Button(localization.text(.historyDeleteConversation), systemImage: "trash", role: .destructive) {
                viewModel.deleteConversation(id: item.id)
            }
        }, preview: {
            historyConversationRowContent(item: item, isCurrent: isCurrent)
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .frame(width: Self.sidebarWidth - 16, alignment: .leading)
                .background(Color(.secondarySystemBackground))
        })
    }

    private func historyConversationRowContent(item: ConversationHistoryItem, isCurrent: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(item.title)
                .font(.system(size: 15, weight: isCurrent ? .semibold : .medium))
                .foregroundStyle(isCurrent ? AppTheme.accent : AppTheme.primaryText)
                .lineLimit(2)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 40, alignment: .topLeading)

            VStack(alignment: .trailing, spacing: 2) {
                Text(Self.historyDateFormatter.string(from: item.updatedAt))
                Text(Self.historyTimeFormatter.string(from: item.updatedAt))
            }
            .font(.system(size: 10, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(AppTheme.secondaryText.opacity(0.74))
            .frame(width: 40, alignment: .topTrailing)
            .padding(.top, 2)
        }
    }

    private func beginCustomTitleEdit(for item: ConversationHistoryItem) {
        renamingConversationID = item.id
        renamingTitleText = item.title
    }

    private func applyCustomTitle() {
        guard let renamingConversationID else { return }
        viewModel.renameConversation(id: renamingConversationID, title: renamingTitleText)
        clearRenamingState()
    }

    private func requestAITitle(for item: ConversationHistoryItem) {
        viewModel.generateTitleForConversation(id: item.id, pinResult: true)
        clearRenamingState()
    }

    private func clearRenamingState() {
        renamingConversationID = nil
        renamingTitleText = ""
    }

    private func applyCustomContextLength() {
        guard let value = Int(customContextLengthInput) else {
            customContextLengthInput = ""
            return
        }
        let clamped = min(max(value, ContextLength.customMin), ContextLength.customMax)
        viewModel.changeContextLength(to: .custom(clamped))
        customContextLengthInput = ""
    }

    private func setSidebar(open: Bool, animated: Bool = true) {
        let applyState = {
            if open {
                dismissKeyboard()
            } else {
                clearRenamingState()
            }
            showSidebar = open
            sidebarDragTranslation = 0
        }

        if animated {
            withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.86, blendDuration: 0.15)) {
                applyState()
            }
        } else {
            applyState()
        }
    }

    private func openSettingsPage() {
        dismissKeyboard()
        sidebarDragTranslation = 0
        showSettings = true
    }

    private var conversationGalleryItems: [GalleryImageItem] {
        viewModel.messages.flatMap { message in
            message.imageAttachments.enumerated().map { index, data in
                GalleryImageItem(id: "\(message.id.uuidString)-\(index)", data: data)
            }
        }
    }

    private func openComposerGallery(at index: Int) {
        let items = selectedImageDataList.enumerated().map { offset, data in
            GalleryImageItem(id: "composer-\(offset)", data: data)
        }
        guard items.indices.contains(index) else { return }
        activeGallery = GalleryPresentation(
            items: items,
            initialIndex: index,
            title: localization.text(.gallerySelectedImages)
        )
    }

    private func openConversationGallery(from message: Message, imageIndex: Int) {
        let items = conversationGalleryItems
        let targetID = "\(message.id.uuidString)-\(imageIndex)"
        guard let targetIndex = items.firstIndex(where: { $0.id == targetID }) else { return }
        activeGallery = GalleryPresentation(
            items: items,
            initialIndex: targetIndex,
            title: localization.text(.galleryConversationImages)
        )
    }
}

// MARK: - ScrollViewFinder（获取 UIScrollView 实时引用）

/// 在 SwiftUI ScrollView 内部放置一个不可见的 UIView，
/// 沿 superview 链向上查找 UIScrollView 并回传引用。
/// 之后可以直接同步读取 isDragging / isDecelerating / contentOffset 等属性。
private struct ScrollViewFinder: UIViewRepresentable {
    var onFound: (UIScrollView) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard context.coordinator.found == false else { return }
        DispatchQueue.main.async {
            var current: UIView? = uiView.superview
            while let view = current {
                if let sv = view as? UIScrollView {
                    context.coordinator.found = true
                    onFound(sv)
                    return
                }
                current = view.superview
            }
        }
    }

    final class Coordinator {
        var found = false
    }
}

#Preview("聊天界面") {
    ChatView()
        .environmentObject(LocalizationManager())
}
