#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

MODEL_PATH="$REPO_ROOT/localAI/Qwen3.5-2B-Q4_K_M.gguf"
PROMPT="你是一个有帮助的助手。请用中文简要自我介绍。"
CTX_SIZE="4096"
MAX_TOKENS="256"
THREADS="$(sysctl -n hw.logicalcpu 2>/dev/null || echo 8)"
GPU_LAYERS="99"
TEMP="0.7"
TOP_P="0.92"
INTERACTIVE="1"
AUTO_BUILD="1"
REBUILD="0"
LLAMA_CPP_DIR="${LLAMA_CPP_DIR:-$HOME/.cache/llama.cpp}"
LLAMA_CPP_REF="${LLAMA_CPP_REF:-master}"
UPDATE_LLAMA_CPP="0"

EXTRA_ARGS=()

print_usage() {
    cat <<USAGE
Usage: $(basename "$0") [options] [-- llama.cpp-extra-args]

Run a local GGUF model with native llama.cpp (llama-cli).

Options:
  --model <path>          GGUF model path (default: $MODEL_PATH)
  --prompt <text>         Prompt text
  --ctx-size <n>          Context length (default: $CTX_SIZE)
  --max-tokens <n>        Max generated tokens (default: $MAX_TOKENS)
  --threads <n>           CPU threads (default: detected logical CPU count)
  --ngl <n>               GPU layers / n-gpu-layers (default: $GPU_LAYERS)
  --temp <n>              Sampling temperature (default: $TEMP)
  --top-p <n>             Top-p (default: $TOP_P)
  --llama-dir <path>      llama.cpp source directory (default: $LLAMA_CPP_DIR)
  --llama-ref <ref>       git ref for llama.cpp update (default: $LLAMA_CPP_REF)
  --update                update existing llama.cpp checkout before build
  --non-interactive       Disable interactive chat mode
  --no-build              Do not auto clone/build llama.cpp
  --rebuild               Force reconfigure and rebuild llama.cpp
  -h, --help              Show this help

Examples:
  $(basename "$0")
  $(basename "$0") --model /path/to/model.gguf --prompt "你好" --max-tokens 64
  $(basename "$0") --non-interactive -- --seed 42
USAGE
}

log() {
    printf '[run-llama-cpp] %s\n' "$*"
}

fail() {
    printf '[run-llama-cpp] ERROR: %s\n' "$*" >&2
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --model)
            MODEL_PATH="$2"
            shift 2
            ;;
        --prompt)
            PROMPT="$2"
            shift 2
            ;;
        --ctx-size)
            CTX_SIZE="$2"
            shift 2
            ;;
        --max-tokens)
            MAX_TOKENS="$2"
            shift 2
            ;;
        --threads)
            THREADS="$2"
            shift 2
            ;;
        --ngl)
            GPU_LAYERS="$2"
            shift 2
            ;;
        --temp)
            TEMP="$2"
            shift 2
            ;;
        --top-p)
            TOP_P="$2"
            shift 2
            ;;
        --llama-dir)
            LLAMA_CPP_DIR="$2"
            shift 2
            ;;
        --llama-ref)
            LLAMA_CPP_REF="$2"
            shift 2
            ;;
        --update)
            UPDATE_LLAMA_CPP="1"
            shift
            ;;
        --non-interactive)
            INTERACTIVE="0"
            shift
            ;;
        --no-build)
            AUTO_BUILD="0"
            shift
            ;;
        --rebuild)
            REBUILD="1"
            shift
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        --)
            shift
            EXTRA_ARGS=("$@")
            break
            ;;
        *)
            fail "unknown argument: $1 (use --help)"
            ;;
    esac
done

if [[ ! -f "$MODEL_PATH" ]]; then
    fail "model file not found: $MODEL_PATH"
fi

find_llama_cli() {
    if command -v llama-cli >/dev/null 2>&1; then
        command -v llama-cli
        return 0
    fi

    local candidates=(
        "$LLAMA_CPP_DIR/build/bin/llama-cli"
        "$LLAMA_CPP_DIR/build/bin/main"
        "$LLAMA_CPP_DIR/bin/llama-cli"
    )

    local path
    for path in "${candidates[@]}"; do
        if [[ -x "$path" ]]; then
            printf '%s\n' "$path"
            return 0
        fi
    done

    return 1
}

build_llama_cpp() {
    if [[ "$AUTO_BUILD" != "1" ]]; then
        fail "llama-cli not found and --no-build is set"
    fi

    mkdir -p "$(dirname "$LLAMA_CPP_DIR")"

    if [[ ! -d "$LLAMA_CPP_DIR/.git" ]]; then
        log "cloning llama.cpp into $LLAMA_CPP_DIR"
        git clone --depth 1 https://github.com/ggerganov/llama.cpp.git "$LLAMA_CPP_DIR"
    elif [[ "$UPDATE_LLAMA_CPP" == "1" ]]; then
        log "updating llama.cpp ($LLAMA_CPP_REF)"
        git -C "$LLAMA_CPP_DIR" fetch --depth 1 origin "$LLAMA_CPP_REF"
        git -C "$LLAMA_CPP_DIR" checkout --detach FETCH_HEAD
    else
        log "using existing llama.cpp checkout at $LLAMA_CPP_DIR"
    fi

    if [[ "$REBUILD" == "1" ]]; then
        rm -rf "$LLAMA_CPP_DIR/build"
    fi

    local cmake_args=(
        -DCMAKE_BUILD_TYPE=Release
        -DLLAMA_BUILD_TESTS=OFF
        -DLLAMA_BUILD_EXAMPLES=ON
    )

    if [[ "$(uname -s)" == "Darwin" ]]; then
        cmake_args+=( -DGGML_METAL=ON )
    fi

    log "configuring llama.cpp"
    cmake -S "$LLAMA_CPP_DIR" -B "$LLAMA_CPP_DIR/build" "${cmake_args[@]}"

    log "building llama.cpp"
    cmake --build "$LLAMA_CPP_DIR/build" --config Release -j
}

LLAMA_CLI_PATH="$(find_llama_cli || true)"
if [[ -z "$LLAMA_CLI_PATH" ]]; then
    build_llama_cpp
    LLAMA_CLI_PATH="$(find_llama_cli || true)"
fi

if [[ -z "$LLAMA_CLI_PATH" ]]; then
    fail "unable to locate llama-cli after build"
fi

log "using llama-cli: $LLAMA_CLI_PATH"
log "using model: $MODEL_PATH"

BASE_ARGS=(
    -m "$MODEL_PATH"
    -c "$CTX_SIZE"
    -n "$MAX_TOKENS"
    -t "$THREADS"
    -ngl "$GPU_LAYERS"
    --temp "$TEMP"
    --top-p "$TOP_P"
    --flash-attn auto
)

if [[ "$INTERACTIVE" == "1" ]]; then
    BASE_ARGS+=( -cnv )
else
    BASE_ARGS+=( -cnv -st --simple-io --no-display-prompt )
fi

if [[ -n "$PROMPT" ]]; then
    BASE_ARGS+=( -p "$PROMPT" )
fi

if [[ ${#EXTRA_ARGS[@]} -gt 0 ]]; then
    BASE_ARGS+=( "${EXTRA_ARGS[@]}" )
fi

log "starting inference"
exec "$LLAMA_CLI_PATH" "${BASE_ARGS[@]}"
