import SwiftUI

struct InputBar: View {
    @Binding var text: String
    let placeholder: String
    let isGenerating: Bool
    let hasAttachment: Bool
    let onSend: () -> Void
    let onStop: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            TextField(placeholder, text: $text, axis: .vertical)
                .lineLimit(1...5)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background {
                    RoundedRectangle(cornerRadius: AppTheme.inputCornerRadius)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: AppTheme.inputCornerRadius)
                                .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                        }
                }
                .foregroundStyle(AppTheme.primaryText)
                .focused($isFocused)
                .onSubmit {
                    if !isGenerating && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        onSend()
                    }
                }

            Button(action: isGenerating ? onStop : onSend) {
                Image(systemName: isGenerating ? "stop.circle.fill" : "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(buttonColor)
            }
            .disabled(!isGenerating && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !hasAttachment)
        }
        .padding(.horizontal, AppTheme.contentPadding)
        .padding(.vertical, 8)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private var buttonColor: Color {
        if isGenerating {
            return .red.opacity(0.9)
        }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !hasAttachment {
            return AppTheme.secondaryText
        }
        return AppTheme.accent
    }
}

#Preview("输入栏") {
    VStack {
        Spacer()
        InputBar(
            text: .constant("你好"),
            placeholder: "输入消息...",
            isGenerating: false,
            hasAttachment: false,
            onSend: {},
            onStop: {}
        )
    }
    .background(AppTheme.backgroundGradient)
    .preferredColorScheme(.dark)
}
