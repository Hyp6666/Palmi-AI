# Phase 1 Design: Local Text Chat with Qwen3.5

## Overview

Build a local AI chat app for iOS using LLM.swift + Qwen3.5-2B with streaming output, glass UI, and context length selection. No network required.

## Architecture

```
localAI/
├── localAIApp.swift              # App entry, dark mode enforcement
├── Models/
│   ├── Message.swift             # Message data model
│   └── ChatViewModel.swift       # LLM.swift wrapper, chat state management
├── Views/
│   ├── ChatView.swift            # Main chat screen
│   ├── MessageBubble.swift       # Individual message bubble
│   └── InputBar.swift            # Text input + send/stop buttons
├── Theme/
│   └── AppTheme.swift            # Colors, fonts, glass material constants
└── Assets.xcassets/
```

## Components

### Data Model — Message

```swift
struct Message: Identifiable {
    let id: UUID
    let role: MessageRole  // .user / .assistant
    var content: String    // var for streaming updates
    let timestamp: Date
}

enum MessageRole {
    case user, assistant
}
```

### ChatViewModel

- Subclass of LLM.swift's `LLM` class
- Init with `Bundle.main.url(forResource: "Qwen3.5-2B-Q4_K_M", withExtension: "gguf")`
- Template: `.chatML(systemPrompt)` — Qwen3.5 uses ChatML format
- `maxTokenCount` parameter controls context window (4096 / 16384 / 32768)
- Published `messages: [Message]` array for UI binding
- Streaming: LLM's `output` property updates in real-time, drive UI refresh
- Stop generation: call `bot.stop()`

### ChatView

- Dark background with gradient overlay
- ScrollView with message bubbles, auto-scroll to bottom
- Top toolbar: model name + context length picker
- Loading state while model initializes

### MessageBubble

- User messages: right-aligned, blue-purple gradient bubble
- AI messages: left-aligned, dark glass (.ultraThinMaterial) bubble
- Rounded corners (16pt)
- Basic text rendering (future: markdown support)

### InputBar

- Text field with glass background
- Send button (paperplane icon) — disabled when empty or generating
- Stop button (xmark icon) — shown during generation
- Keyboard-aware positioning

## Model Loading

- GGUF file bundled in app (Copy Bundle Resources)
- ~2.1GB for Q3_K_M quantization
- Loading screen shown during initialization
- Model file excluded from git via .gitignore

## Context Length Selection

- Three tiers: 4K (default), 16K, 32K
- Changing context requires re-initializing LLM instance
- Conversation history cleared on context change
- Warning shown before clearing

## UI Design

- Force dark mode: `.preferredColorScheme(.dark)`
- Background: dark gradient (black → dark blue/purple)
- Glass layers: `.ultraThinMaterial` for bubbles and input bar
- Accent color: blue-purple for interactive elements
- System font with appropriate dynamic type sizes

## Memory Considerations

- 4B Q3_K_M: ~2.1GB model weight
- 4K context: ~50MB additional
- 16K context: ~200MB additional
- 32K context: ~400MB additional
- iPhone 15 (6GB RAM) can handle 4K/16K comfortably; 32K needs testing

## Dependencies

- LLM.swift (SPM, branch: main) — llama.cpp wrapper for Swift

## Out of Scope (Phase 1)

- Multimodal/image input (Phase 2)
- ODR model download (Phase 2)
- Model switching 4B ↔ other sizes (Phase 2)
- Settings page (Phase 2)
- Markdown rendering (future enhancement)
- Conversation persistence (future enhancement)
