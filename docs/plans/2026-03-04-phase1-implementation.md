# Phase 1 Implementation Plan: Local Text Chat

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a working local AI chat app with Qwen3.5-2B, streaming output, glass UI, and context length selection.

**Architecture:** Composition-based ViewModel wrapping LLM.swift's `LLM` class. SwiftUI views with glass material design. File system synchronized groups (Xcode 26) auto-detect new Swift files.

**Tech Stack:** SwiftUI, LLM.swift (SPM), llama.cpp (via LLM.swift xcframework), Combine

---

### Task 1: Add LLM.swift SPM Dependency

**Files:**
- Modify: `localAI.xcodeproj/project.pbxproj` (via Xcode UI)

**Step 1: Add SPM package in Xcode**

This must be done by the user in Xcode:
1. Open `localAI.xcodeproj` in Xcode
2. File → Add Package Dependencies...
3. Enter URL: `https://github.com/eastriverlee/LLM.swift/`
4. Set "Dependency Rule" to "Branch" → `main`
5. Click "Add Package"
6. In the dialog, ensure "LLM" library is checked and target is "localAI"
7. Click "Add Package"

**Step 2: Verify dependency resolves**

Build the project (Cmd+B). Expected: build succeeds with LLM package resolved.

**Step 3: Commit**

```bash
git add localAI.xcodeproj/project.pbxproj localAI.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
git commit -m "feat: add LLM.swift SPM dependency"
```

---

### Task 2: Create .gitignore and Project Config

**Files:**
- Create: `.gitignore`

**Step 1: Create .gitignore**

```gitignore
# Model files (too large for git)
*.gguf

# Xcode user data
xcuserdata/
*.xcuserstate
*.xcuserdatad/

# Build products
build/
DerivedData/
*.xcarchive

# OS files
.DS_Store
```

**Step 2: Commit**

```bash
git add .gitignore
git commit -m "chore: add .gitignore excluding model files and build artifacts"
```

---

### Task 3: Create AppTheme.swift

**Files:**
- Create: `localAI/Theme/AppTheme.swift`

**Step 1: Create the directory and file**

```swift
import SwiftUI

enum AppTheme {
    // MARK: - Background
    static let backgroundGradient = LinearGradient(
        colors: [
            Color(red: 0.05, green: 0.05, blue: 0.12),
            Color(red: 0.08, green: 0.06, blue: 0.18),
            Color(red: 0.04, green: 0.04, blue: 0.10)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: - Bubble Colors
    static let userBubbleGradient = LinearGradient(
        colors: [
            Color(red: 0.35, green: 0.40, blue: 0.95),
            Color(red: 0.45, green: 0.35, blue: 0.85)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let aiBubbleColor = Color.white.opacity(0.08)

    // MARK: - Text Colors
    static let primaryText = Color.white
    static let secondaryText = Color.white.opacity(0.6)

    // MARK: - Accent
    static let accent = Color(red: 0.45, green: 0.50, blue: 1.0)

    // MARK: - Layout
    static let bubbleCornerRadius: CGFloat = 18
    static let inputCornerRadius: CGFloat = 22
    static let contentPadding: CGFloat = 16
}
```

**Step 2: Verify build**

Build the project (Cmd+B). File system sync should auto-detect the new file.
Expected: build succeeds.

**Step 3: Commit**

```bash
git add localAI/Theme/
git commit -m "feat: add AppTheme with glass UI color definitions"
```

---

### Task 4: Create Message.swift Data Model

**Files:**
- Create: `localAI/Models/Message.swift`

**Step 1: Create the file**

```swift
import Foundation

enum MessageRole: Sendable {
    case user
    case assistant
}

struct Message: Identifiable, Sendable {
    let id: UUID
    let role: MessageRole
    var content: String
    let timestamp: Date

    init(role: MessageRole, content: String) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
    }
}
```

**Step 2: Verify build**

Build (Cmd+B). Expected: succeeds.

**Step 3: Commit**

```bash
git add localAI/Models/
git commit -m "feat: add Message data model"
```

---

### Task 5: Create ChatViewModel.swift

**Files:**
- Create: `localAI/Models/ChatViewModel.swift`

**Step 1: Create the ViewModel**

This wraps LLM.swift's `LLM` class with Combine to forward output changes for streaming UI.

```swift
import SwiftUI
import LLM
import Combine

enum ContextLength: String, CaseIterable, Identifiable {
    case standard = "4K"
    case enhanced = "16K"
    case maximum = "32K"

    var id: String { rawValue }

    var tokenCount: Int {
        switch self {
        case .standard: return 4096
        case .enhanced: return 16384
        case .maximum: return 32768
        }
    }
}

@MainActor
class ChatViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published private(set) var isGenerating = false
    @Published private(set) var isLoading = true
    @Published private(set) var loadError: String?
    @Published var currentStreamingText = ""
    @Published var contextLength: ContextLength = .standard

    private var bot: LLM?
    private var outputCancellable: AnyCancellable?

    private static let modelName = "Qwen3.5-2B-Q4_K_M"
    private static let systemPrompt = "你是厚普（Hope），一个友好的本地AI助手。你运行在用户的设备上，完全离线，保护用户隐私。请用简洁、自然的中文回答问题。"

    func loadModel() {
        isLoading = true
        loadError = nil

        guard let url = Bundle.main.url(forResource: Self.modelName, withExtension: "gguf") else {
            loadError = "找不到模型文件 \(Self.modelName).gguf"
            isLoading = false
            return
        }

        guard let llm = LLM(from: url, template: .chatML(Self.systemPrompt), maxTokenCount: contextLength.tokenCount) else {
            loadError = "模型加载失败"
            isLoading = false
            return
        }

        bot = llm

        // Forward LLM output changes to our published property for streaming UI
        outputCancellable = llm.$output
            .receive(on: RunLoop.main)
            .sink { [weak self] newOutput in
                guard let self, self.isGenerating else { return }
                self.currentStreamingText = newOutput
            }

        isLoading = false
    }

    func send(_ text: String) async {
        guard let bot, !isGenerating else { return }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        messages.append(Message(role: .user, content: trimmed))
        isGenerating = true
        currentStreamingText = ""

        await bot.respond(to: trimmed)

        let finalOutput = bot.output
        messages.append(Message(role: .assistant, content: finalOutput))
        currentStreamingText = ""
        isGenerating = false
    }

    func stop() {
        bot?.stop()
    }

    func changeContextLength(to length: ContextLength) {
        guard length != contextLength else { return }
        contextLength = length
        messages.removeAll()
        currentStreamingText = ""
        outputCancellable = nil
        bot = nil
        loadModel()
    }

    func clearConversation() {
        messages.removeAll()
        currentStreamingText = ""
        bot?.history.removeAll()
    }
}
```

**Step 2: Verify build**

Build (Cmd+B). Expected: succeeds (LLM import resolves via SPM).

**Step 3: Commit**

```bash
git add localAI/Models/ChatViewModel.swift
git commit -m "feat: add ChatViewModel wrapping LLM.swift with streaming support"
```

---

### Task 6: Create MessageBubble.swift

**Files:**
- Create: `localAI/Views/MessageBubble.swift`

**Step 1: Create the bubble component**

```swift
import SwiftUI

struct MessageBubble: View {
    let message: Message
    let isStreaming: Bool

    init(message: Message, isStreaming: Bool = false) {
        self.message = message
        self.isStreaming = isStreaming
    }

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 60) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                Text(message.content + (isStreaming ? "▊" : ""))
                    .foregroundStyle(AppTheme.primaryText)
                    .textSelection(.enabled)
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

            if !isUser { Spacer(minLength: 60) }
        }
    }
}
```

**Step 2: Verify build**

Build (Cmd+B). Expected: succeeds.

**Step 3: Commit**

```bash
git add localAI/Views/
git commit -m "feat: add MessageBubble with glass material for AI and gradient for user"
```

---

### Task 7: Create InputBar.swift

**Files:**
- Create: `localAI/Views/InputBar.swift`

**Step 1: Create the input bar component**

```swift
import SwiftUI

struct InputBar: View {
    @Binding var text: String
    let isGenerating: Bool
    let onSend: () -> Void
    let onStop: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            TextField("输入消息...", text: $text, axis: .vertical)
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
            .disabled(!isGenerating && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return AppTheme.secondaryText
        }
        return AppTheme.accent
    }
}
```

**Step 2: Verify build**

Build (Cmd+B). Expected: succeeds.

**Step 3: Commit**

```bash
git add localAI/Views/InputBar.swift
git commit -m "feat: add InputBar with glass material and send/stop toggle"
```

---

### Task 8: Create ChatView.swift

**Files:**
- Create: `localAI/Views/ChatView.swift`

**Step 1: Create the main chat view**

```swift
import SwiftUI

struct ChatView: View {
    @StateObject private var viewModel = ChatViewModel()
    @State private var inputText = ""

    var body: some View {
        ZStack {
            AppTheme.backgroundGradient
                .ignoresSafeArea()

            if viewModel.isLoading {
                loadingView
            } else if let error = viewModel.loadError {
                errorView(error)
            } else {
                chatContent
            }
        }
        .preferredColorScheme(.dark)
        .task {
            viewModel.loadModel()
        }
    }

    // MARK: - Chat Content

    private var chatContent: some View {
        VStack(spacing: 0) {
            headerBar

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.messages) { message in
                            MessageBubble(message: message)
                        }

                        if viewModel.isGenerating {
                            MessageBubble(
                                message: Message(role: .assistant, content: viewModel.currentStreamingText),
                                isStreaming: true
                            )
                            .id("streaming")
                        }
                    }
                    .padding(.horizontal, AppTheme.contentPadding)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                }
                .onChange(of: viewModel.currentStreamingText) {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo("streaming", anchor: .bottom)
                    }
                }
                .onChange(of: viewModel.messages.count) {
                    if let lastID = viewModel.messages.last?.id {
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(lastID, anchor: .bottom)
                        }
                    }
                }
            }

            InputBar(text: $inputText, isGenerating: viewModel.isGenerating) {
                sendMessage()
            } onStop: {
                viewModel.stop()
            }
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("厚普")
                    .font(.headline)
                    .foregroundStyle(AppTheme.primaryText)
                Text("Qwen3.5-2B · 本地运行")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }

            Spacer()

            Menu {
                ForEach(ContextLength.allCases) { length in
                    Button {
                        viewModel.changeContextLength(to: length)
                    } label: {
                        HStack {
                            Text(length.rawValue)
                            if length == viewModel.contextLength {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "text.alignleft")
                    Text(viewModel.contextLength.rawValue)
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

            Button {
                viewModel.clearConversation()
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .padding(.horizontal, AppTheme.contentPadding)
        .padding(.vertical, 10)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea(edges: .top)
        }
    }

    // MARK: - Loading & Error

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(AppTheme.accent)
            Text("正在加载模型...")
                .foregroundStyle(AppTheme.secondaryText)
        }
    }

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.yellow)
            Text(error)
                .foregroundStyle(AppTheme.primaryText)
                .multilineTextAlignment(.center)
            Button("重试") {
                viewModel.loadModel()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    // MARK: - Actions

    private func sendMessage() {
        let text = inputText
        inputText = ""
        Task {
            await viewModel.send(text)
        }
    }
}
```

**Step 2: Verify build**

Build (Cmd+B). Expected: succeeds.

**Step 3: Commit**

```bash
git add localAI/Views/ChatView.swift
git commit -m "feat: add ChatView with streaming messages, header, and context picker"
```

---

### Task 9: Update localAIApp.swift and Remove ContentView.swift

**Files:**
- Modify: `localAI/localAIApp.swift`
- Delete: `localAI/ContentView.swift`

**Step 1: Update localAIApp.swift**

Replace the entire file content:

```swift
import SwiftUI

@main
struct localAIApp: App {
    var body: some Scene {
        WindowGroup {
            ChatView()
        }
    }
}
```

**Step 2: Delete ContentView.swift**

```bash
rm localAI/ContentView.swift
```

**Step 3: Verify build**

Build (Cmd+B). Expected: succeeds with ChatView as the root view.

**Step 4: Commit**

```bash
git add localAI/localAIApp.swift
git rm localAI/ContentView.swift
git commit -m "feat: set ChatView as root view, remove placeholder ContentView"
```

---

### Task 10: Place Model File and Full Verification

**Files:**
- Add: `localAI/Qwen3.5-2B-Q4_K_M.gguf` (user action)

**Step 1: User places model file**

The user must:
1. Rename their model file to `Qwen3.5-2B-Q4_K_M.gguf`
2. Copy it to `localAI/` folder on disk (same folder as `localAIApp.swift`)
3. Xcode file system sync should auto-detect it

**Step 2: Verify in Xcode**

In Xcode, check the `localAI` group in the project navigator. The `.gguf` file should appear. Click on it and verify:
- Target Membership: `localAI` is checked
- This ensures it gets copied into the app bundle

**Step 3: Build and run on simulator**

Build and run (Cmd+R) on iPhone 15 Pro simulator. Expected behavior:
1. App launches with dark background
2. Loading spinner shows "正在加载模型..."
3. Model loads (may be slow on simulator)
4. Chat interface appears with header, empty message area, and input bar
5. Type a message and send — AI responds with streaming text
6. Context length picker works in header

> Note: Simulator performance will be much slower than real device. For proper testing, use a physical iPhone 15 or later.

**Step 4: Commit (no model file — it's gitignored)**

```bash
git status  # verify .gguf is not staged
git add -A
git commit -m "chore: final verification pass"
```

---

## File Summary

| File | Action | Purpose |
|------|--------|---------|
| `.gitignore` | Create | Exclude model files and build artifacts |
| `localAI/Theme/AppTheme.swift` | Create | UI colors, gradients, layout constants |
| `localAI/Models/Message.swift` | Create | Chat message data model |
| `localAI/Models/ChatViewModel.swift` | Create | LLM.swift wrapper, streaming, state management |
| `localAI/Views/MessageBubble.swift` | Create | Message bubble with glass/gradient styles |
| `localAI/Views/InputBar.swift` | Create | Text input + send/stop button |
| `localAI/Views/ChatView.swift` | Create | Main chat screen composing all views |
| `localAI/localAIApp.swift` | Modify | Point root to ChatView |
| `localAI/ContentView.swift` | Delete | Remove placeholder |

## Dependencies

- **LLM.swift** (SPM, branch: main): Must be added by user in Xcode before Task 3.

## User Actions Required

1. **Task 1**: Add LLM.swift package in Xcode UI
2. **Task 10**: Copy and rename GGUF model file to `localAI/Qwen3.5-2B-Q4_K_M.gguf`
