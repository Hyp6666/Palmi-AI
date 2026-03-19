import SwiftUI
import MarkdownUI

struct MessageBubble: View, Equatable {
    let message: Message
    let isStreaming: Bool
    let isImageProcessingPlaceholder: Bool
    let usesMarkdown: Bool
    let isThinkingExpanded: Bool
    let canToggleThinking: Bool
    let onToggleThinking: () -> Void
    let onOpenImageAtIndex: ((Int) -> Void)?
    @EnvironmentObject private var localization: LocalizationManager

    init(
        message: Message,
        isStreaming: Bool = false,
        isImageProcessingPlaceholder: Bool = false,
        usesMarkdown: Bool,
        isThinkingExpanded: Bool,
        canToggleThinking: Bool,
        onToggleThinking: @escaping () -> Void,
        onOpenImageAtIndex: ((Int) -> Void)? = nil
    ) {
        self.message = message
        self.isStreaming = isStreaming
        self.isImageProcessingPlaceholder = isImageProcessingPlaceholder
        self.usesMarkdown = usesMarkdown
        self.isThinkingExpanded = isThinkingExpanded
        self.canToggleThinking = canToggleThinking
        self.onToggleThinking = onToggleThinking
        self.onOpenImageAtIndex = onOpenImageAtIndex
    }

    private var isUser: Bool { message.role == .user }
    private var thinkingText: String { message.thinking ?? "" }
    private var displayContent: String {
        isImageProcessingPlaceholder ? localization.text(.attachmentImageProcessingWait) : message.content
    }

    private var shouldShowContentBubble: Bool {
        !displayContent.isEmpty || (isStreaming && thinkingText.isEmpty)
    }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 60) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                if !message.imageAttachments.isEmpty {
                    imageStrip
                }

                if !isUser, !thinkingText.isEmpty {
                    thinkingSection
                }

                if shouldShowContentBubble {
                    contentView
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background {
                            if isUser {
                                RoundedRectangle(cornerRadius: AppTheme.bubbleCornerRadius)
                                    .fill(AppTheme.userBubbleGradient)
                            } else {
                                RoundedRectangle(cornerRadius: AppTheme.bubbleCornerRadius)
                                    .fill(.ultraThinMaterial)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: AppTheme.bubbleCornerRadius)
                                            .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                                    }
                            }
                        }
                }
            }

            if !isUser { Spacer(minLength: 60) }
        }
    }

    @ViewBuilder
    private var imageStrip: some View {
        let images = decodedImages

        if images.count == 1, let first = images.first {
            imageThumbnail(image: first.image, index: first.index, size: 180)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(images, id: \.index) { item in
                        imageThumbnail(image: item.image, index: item.index, size: 132)
                    }
                }
            }
            .frame(maxWidth: 220, alignment: isUser ? .trailing : .leading)
        }
    }

    @ViewBuilder
    private var contentView: some View {
        let text = displayContent + ((isStreaming && !isImageProcessingPlaceholder) ? "▊" : "")
        if isUser || !usesMarkdown {
            PlainTextMessageView(text: text, color: AppTheme.primaryText, font: .body)
        } else {
            MarkdownTextView(text: text, color: AppTheme.primaryText, baseTextScale: 1.0)
        }
    }

    private var thinkingSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: onToggleThinking) {
                HStack(spacing: 6) {
                    Image(systemName: isThinkingExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                    Text(localization.text(.reasoningThinking))
                        .font(.caption2)
                }
                .foregroundStyle(AppTheme.secondaryText)
            }
            .buttonStyle(.plain)
            .disabled(!canToggleThinking)

            if isThinkingExpanded {
                ThinkingTextView(
                    text: thinkingText + (isStreaming ? "▊" : ""),
                    color: AppTheme.secondaryText.opacity(0.95),
                    font: .system(size: 13, weight: .regular, design: .monospaced)
                )
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.04))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                        }
                }
            }
        }
        .padding(.leading, 2)
    }

    private var decodedImages: [(index: Int, image: UIImage)] {
        message.imageAttachments.enumerated().compactMap { offset, data in
            guard let image = UIImage(data: data) else { return nil }
            return (index: offset, image: image)
        }
    }

    private func imageThumbnail(image: UIImage, index: Int, size: CGFloat) -> some View {
        Button {
            onOpenImageAtIndex?(index)
        } label: {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    static func == (lhs: MessageBubble, rhs: MessageBubble) -> Bool {
        lhs.isStreaming == rhs.isStreaming
        && lhs.isImageProcessingPlaceholder == rhs.isImageProcessingPlaceholder
        && lhs.usesMarkdown == rhs.usesMarkdown
        && lhs.isThinkingExpanded == rhs.isThinkingExpanded
        && lhs.canToggleThinking == rhs.canToggleThinking
        && lhs.message.id == rhs.message.id
        && lhs.message.content == rhs.message.content
        && lhs.message.thinking == rhs.message.thinking
        && lhs.message.imageAttachments.count == rhs.message.imageAttachments.count
    }
}

private struct PlainTextMessageView: View {
    let text: String
    let color: Color
    let font: Font

    var body: some View {
        Text(verbatim: text)
            .font(font)
            .foregroundStyle(color)
            .textSelection(.enabled)
    }
}

private struct ThinkingTextView: View {
    let text: String
    let color: Color
    let font: Font

    var body: some View {
        Text(verbatim: text)
            .font(font)
            .foregroundStyle(color)
            .lineSpacing(3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.disabled)
    }
}

private struct MarkdownTextView: View {
    let text: String
    let color: Color
    let baseTextScale: Double

    var body: some View {
        Markdown(normalizedMarkdown)
            .markdownTheme(.basic)
            .markdownTextStyle {
                FontSize(.em(baseTextScale))
                ForegroundColor(color)
                BackgroundColor(nil)
            }
            .foregroundStyle(color)
            .textSelection(.enabled)
    }

    private var normalizedMarkdown: String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }
}

#Preview("对话气泡") {
    VStack(spacing: 12) {
        MessageBubble(
            message: Message(role: .user, content: "你好，请介绍一下你自己"),
            usesMarkdown: false,
            isThinkingExpanded: false,
            canToggleThinking: true,
            onToggleThinking: {}
        )
        MessageBubble(
            message: Message(role: .assistant, content: "你好！我是厚普，一个运行在你设备上的本地AI助手。"),
            usesMarkdown: true,
            isThinkingExpanded: false,
            canToggleThinking: true,
            onToggleThinking: {}
        )
        MessageBubble(
            message: Message(
                role: .assistant,
                content: "这是最终回答。",
                thinking: "这是内部思考过程，会以更轻量样式展示。"
            ),
            isStreaming: true,
            usesMarkdown: false,
            isThinkingExpanded: false,
            canToggleThinking: true,
            onToggleThinking: {}
        )
    }
    .padding()
    .background(AppTheme.backgroundGradient)
    .preferredColorScheme(.dark)
    .environmentObject(LocalizationManager())
}
