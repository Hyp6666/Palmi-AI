# Palmi AI

**On-device multimodal AI assistant for iOS, iPadOS, and macOS.**

Palmi AI runs a large language model entirely on your device — no cloud, no accounts, no data collection. Chat offline, ask everyday questions, and explore image-based conversations in a simple, focused app.

> Just want to use it? Skip the build and grab it on the [App Store](https://apps.apple.com/app/palmi-ai/id6760237647) for ~$2.99.

<p align="center">
  <img src="docs/screenshots/01-home.png" width="200" />
  <img src="docs/screenshots/02-chat.png" width="200" />
  <img src="docs/screenshots/03-multimodal.png" width="200" />
  <img src="docs/screenshots/04-markdown.png" width="200" />
</p>

## Features

- **100% On-Device** — Runs Qwen3.5-2B locally via llama.cpp. No internet required.
- **Multimodal** — Text and image input supported.
- **Markdown Rendering** — Tables, lists, and formatted output.
- **Thinking Mode** — Step-by-step reasoning for complex questions.
- **5 Chat Styles** — Default, Efficient, Enthusiastic, Gentle, Serious.
- **Custom Context Length** — Adjustable from 100 to 262,143 tokens.
- **AI Title Generation** — Auto-generate conversation titles.
- **10+ Languages** — English, 简体中文, 繁體中文, 日本語, 한국어, Français, and more.
- **Local Chat History** — All conversations stored on-device.

<p align="center">
  <img src="docs/screenshots/05-context.png" width="200" />
  <img src="docs/screenshots/08-style.png" width="200" />
  <img src="docs/screenshots/07-language.png" width="200" />
  <img src="docs/screenshots/09-reasoning.png" width="200" />
</p>

## Requirements

- iPhone or iPad (A14 chip or later recommended)
- Mac with Apple Silicon (M1 or later)
- 6GB+ RAM recommended for optimal performance
- iOS 26.1 / macOS 26.1 or later
- Xcode 26+ (for building from source)

## Building from Source

1. **Clone the repo**

   ```bash
   git clone https://github.com/Hyp6666/localAI.git
   cd localAI
   ```

2. **Open in Xcode**

   ```bash
   open localAI.xcodeproj
   ```

   Xcode will automatically resolve SPM dependencies (LLM.swift, swift-markdown-ui, etc.).

3. **Download a model**

   Download a GGUF model and its corresponding multimodal projection file, then place both in the `localAI/` directory. Tested models:

   | Model | Files | Total Size | Link |
   |-------|-------|------------|------|
   | Qwen3.5-2B | Q4_K_M.gguf + mmproj-bf16.gguf | ~1.9 GB | [ModelScope](https://modelscope.cn/models/unsloth/Qwen3.5-2B-GGUF/files) |
   | Qwen3.5-4B | Q4_K_M.gguf + mmproj-bf16.gguf | ~3.4 GB | [ModelScope](https://modelscope.cn/models/unsloth/Qwen3.5-4B-GGUF/files) |

   Download both files (model + mmproj) and place them in the `localAI/` directory. The `mmproj` file enables image input (multimodal). Other GGUF-format models may also work.

4. **Build & Run**

   Select your target device and press `Cmd+R`.

> **Note:** Building from source requires downloading a ~2GB model file, configuring Xcode, and a compatible Apple Silicon device. If that sounds like too much work, the [App Store version](https://apps.apple.com/app/palmi-ai/id6760237647) comes ready to go.

## Tech Stack

| Component | Technology |
|-----------|-----------|
| UI | SwiftUI |
| LLM Runtime | llama.cpp (via [LLM.swift](https://github.com/eastriverlee/LLM.swift)) |
| Markdown | [swift-markdown-ui](https://github.com/gonzalezreal/swift-markdown-ui) |
| Image Loading | [NetworkImage](https://github.com/gonzalezreal/NetworkImage) |

## Privacy

Palmi AI collects **zero** data. Everything runs on your device. No analytics, no telemetry, no accounts.

## Acknowledgments

- [Qwen3.5](https://github.com/QwenLM/Qwen3.5) by Alibaba Cloud — Apache 2.0
- [Unsloth](https://github.com/unslothai/unsloth) for GGUF quantized models — Apache 2.0

## License

MIT License — see [LICENSE](LICENSE) for details.

## Support

If you like Palmi AI, the best way to support development is to [buy it on the App Store](https://apps.apple.com/app/palmi-ai/id6760237647).
