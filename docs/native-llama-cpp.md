# 使用原生 llama.cpp 运行 GGUF

这个项目现在提供了一个独立脚本，可以绕开当前 App 封装，直接使用官方 `llama.cpp` 运行本地 `GGUF`。

## 一键运行

在仓库根目录执行：

```bash
./scripts/run-llama-cpp.sh
```

脚本会按顺序执行：

1. 检查系统里是否已有 `llama-cli`
2. 若没有，则自动克隆并编译 `llama.cpp` 到 `~/.cache/llama.cpp`
3. 使用默认模型 `localAI/Qwen3.5-2B-Q4_K_M.gguf` 启动推理

## 常用参数

```bash
./scripts/run-llama-cpp.sh \
  --model /absolute/path/to/your-model.gguf \
  --ctx-size 4096 \
  --max-tokens 128 \
  --threads 8 \
  --ngl 99 \
  --temp 0.7 \
  --top-p 0.92 \
  --prompt "用一句话解释什么是GGUF"
```

## 透传原生 llama.cpp 参数

用 `--` 把后续参数直接传给 `llama-cli`：

```bash
./scripts/run-llama-cpp.sh -- --seed 42
```

## 关闭交互会话模式

默认会开启 `-cnv`（对话模式）。如需单次非交互推理：

```bash
./scripts/run-llama-cpp.sh --non-interactive
```

这个模式会自动附加 `-st --simple-io --no-display-prompt`，生成一轮后自动退出，适合脚本化调用。

## 仅使用已有 llama-cli（不自动构建）

```bash
./scripts/run-llama-cpp.sh --no-build
```

当你系统里已经有可用的 `llama-cli` 时，这个模式最干净。

## 可选更新 llama.cpp

默认不会每次运行都拉最新，避免引入不稳定变更。需要时手动更新：

```bash
./scripts/run-llama-cpp.sh --update
```
