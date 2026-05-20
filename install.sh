#!/bin/bash
# Qubes Translation Qube - 一键安装脚本
# 用法: ./install.sh [--download-model]
#
# 自动安装流程:
#   1. 检查系统依赖 (git, cmake, build-essential, python3)
#   2. 编译 llama.cpp (最新版，支持 TQ1_0/TQ2_0 量化)
#   3. 安装 Python 依赖 (requests, tqdm)
#   4. 创建翻译脚本和配置文件
#   5. (可选) 下载翻译模型

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LLAMA_CPP_DIR="$SCRIPT_DIR/llama.cpp"

# ── 检查 Qubes OS ──────────────────────────────────
check_qubes() {
    if [ -f /etc/qubes-release ]; then
        info "检测到 Qubes OS 环境"
    else
        warn "未检测到 Qubes OS，某些功能可能不可用"
    fi
}

# ── 检查系统要求 ──────────────────────────────────
check_requirements() {
    info "检查系统要求..."

    local mem_mb=$(free -m | awk '/^Mem:/{print $2}')
    if [ "$mem_mb" -lt 500 ]; then
        error "系统内存 ${mem_mb}MB，需要至少 500MB"
    elif [ "$mem_mb" -lt 1000 ]; then
        warn "系统内存 ${mem_mb}MB，刚好够用"
    else
        info "内存检查通过: ${mem_mb}MB"
    fi

    local disk_gb=$(df -BG "$SCRIPT_DIR" | awk 'NR==2{print $4}' | sed 's/G//')
    if [ "$disk_gb" -lt 2 ]; then
        error "磁盘空间不足，需要至少 2GB，当前可用 ${disk_gb}GB"
    else
        info "磁盘空间检查通过: ${disk_gb}GB 可用"
    fi
}

# ── 安装系统依赖 ──────────────────────────────────
install_dependencies() {
    info "安装系统依赖..."

    sudo apt-get update -qq
    sudo apt-get install -y -qq \
        python3 python3-pip python3-venv \
        curl wget git \
        xclip \
        build-essential cmake \
        > /dev/null 2>&1

    info "系统依赖安装完成"
}

# ── 编译 llama.cpp ─────────────────────────────────
build_llama_cpp() {
    info "编译 llama.cpp..."

    if [ -d "$LLAMA_CPP_DIR" ]; then
        info "llama.cpp 目录已存在，更新..."
        cd "$LLAMA_CPP_DIR"
        git pull --ff-only 2>/dev/null || warn "git pull 失败，使用已有版本"
    else
        info "克隆 llama.cpp..."
        git clone --depth 1 https://github.com/ggml-org/llama.cpp.git "$LLAMA_CPP_DIR"
        cd "$LLAMA_CPP_DIR"
    fi

    # 编译（只编译 llama-cli，不需要全部）
    cmake -B build -DCMAKE_BUILD_TYPE=Release -DGGML_CUDA=OFF -DGGML_VULKAN=OFF
    cmake --build build --config Release -j$(nproc) --target llama-cli

    # 验证
    if [ ! -f "build/bin/llama-cli" ]; then
        error "llama-cli 编译失败"
    fi

    # 创建符号链接到项目目录
    ln -sf "$LLAMA_CPP_DIR/build/bin/llama-cli" "$SCRIPT_DIR/llama-cli"

    info "llama.cpp 编译完成"
}

# ── 安装 Python 依赖 ──────────────────────────────
install_python_deps() {
    info "安装 Python 依赖..."

    cat > "$SCRIPT_DIR/requirements.txt" << 'EOF'
requests>=2.28.0
tqdm>=4.64.0
EOF

    pip install -r "$SCRIPT_DIR/requirements.txt" -q --resume-retries 5

    info "Python 依赖安装完成"
}

# ── 下载模型 ───────────────────────────────────────
download_model() {
    info "下载翻译模型..."

    mkdir -p "$SCRIPT_DIR/models"

    local model_file="Hy-MT1.5-1.8B-1.25bit.gguf"
    local model_path="$SCRIPT_DIR/models/$model_file"
    local hf_url="https://huggingface.co/AngelSlim/Hy-MT1.5-1.8B-1.25bit-GGUF/resolve/main/$model_file"
    local mirror_url="https://hf-mirror.com/AngelSlim/Hy-MT1.5-1.8B-1.25bit-GGUF/resolve/main/$model_file"

    if [ -f "$model_path" ]; then
        warn "模型文件已存在，跳过下载"
        return 0
    fi

    info "下载模型文件（约 440MB）..."
    info "尝试从 HuggingFace 下载..."

    if curl -L --progress-bar -o "$model_path" "$hf_url" 2>&1; then
        info "模型下载完成（HuggingFace）"
    else
        warn "HuggingFace 下载失败，尝试镜像..."
        curl -L --progress-bar -o "$model_path" "$mirror_url" || {
            error "模型下载失败，请检查网络连接"
        }
        info "模型下载完成（镜像）"
    fi
}

# ── 创建翻译脚本 ───────────────────────────────────
create_translate_script() {
    info "创建翻译脚本..."

    cat > "$SCRIPT_DIR/translate.py" << 'PYEOF'
#!/usr/bin/env python3
"""
Qubes Translation Qube - 翻译服务
基于腾讯混元 HY-MT1.5 翻译模型，使用 llama-cli 推理
"""

import os
import sys
import json
import time
import subprocess
from pathlib import Path

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

# 默认配置
DEFAULT_CONFIG = {
    "model_path": "models/Hy-MT1.5-1.8B-1.25bit.gguf",
    "llama_cli_path": "./llama-cli",
    "default_source_lang": "auto",
    "default_target_lang": "English",
    "clipboard_poll_interval": 0.5,
    "max_tokens": 512,
    "temperature": 0.7,
    "top_k": 20,
    "top_p": 0.6,
    "repetition_penalty": 1.05,
    "n_threads": 4,
    "n_ctx": 2048,
}

# 支持的语言
LANGUAGES = {
    "zh": "Chinese", "en": "English", "fr": "French",
    "ja": "Japanese", "ko": "Korean", "de": "German",
    "es": "Spanish", "ru": "Russian", "ar": "Arabic",
    "pt": "Portuguese", "it": "Italian", "th": "Thai",
    "vi": "Vietnamese", "id": "Indonesian", "ms": "Malay",
    "tl": "Filipino", "hi": "Hindi", "pl": "Polish",
    "cs": "Czech", "nl": "Dutch", "km": "Khmer",
    "my": "Burmese", "fa": "Persian", "gu": "Gujarati",
    "ur": "Urdu", "te": "Telugu", "mr": "Marathi",
    "he": "Hebrew", "bn": "Bengali", "ta": "Tamil",
    "uk": "Ukrainian", "bo": "Tibetan", "kk": "Kazakh",
    "mn": "Mongolian", "ug": "Uyghur", "yue": "Cantonese",
    "zh-Hant": "Traditional Chinese",
}

# 模型停止标记
STOP_TOKENS = ["<｜hy_end▁of▁sentence｜>", "<｜hy_EOT｜>"]


class TranslationService:
    def __init__(self, config_path="config.json"):
        self.config = self.load_config(config_path)
        self.source_lang = self.config["default_source_lang"]
        self.target_lang = self.config["default_target_lang"]
        self.last_clipboard = ""
        self.llama_ready = False

    def load_config(self, config_path):
        config = DEFAULT_CONFIG.copy()
        cfg = os.path.join(SCRIPT_DIR, config_path)
        if os.path.exists(cfg):
            with open(cfg, 'r', encoding='utf-8') as f:
                user_config = json.load(f)
                config.update(user_config)
        return config

    def resolve_path(self, path):
        """解析相对于项目目录的路径"""
        if os.path.isabs(path):
            return path
        return os.path.join(SCRIPT_DIR, path)

    def load_model(self):
        """验证 llama-cli 和模型文件可用"""
        llama_cli = self.resolve_path(self.config["llama_cli_path"])
        model_path = self.resolve_path(self.config["model_path"])

        if not os.path.exists(model_path):
            print(f"错误: 模型文件不存在: {model_path}")
            print("请运行 ./install.sh --download-model 下载模型")
            return False

        if not os.path.exists(llama_cli):
            # 尝试在 PATH 中查找
            result = subprocess.run(['which', 'llama-cli'],
                                    capture_output=True, text=True)
            if result.returncode == 0:
                self.config["llama_cli_path"] = result.stdout.strip()
            else:
                print(f"错误: llama-cli 未找到: {llama_cli}")
                print("请运行 ./install.sh 编译 llama.cpp")
                return False

        # 快速验证模型可加载
        print("正在验证模型...")
        result = subprocess.run(
            [self.config["llama_cli_path"], '-m', model_path,
             '-p', 'hello', '-n', '1', '-c', '64',
             '--no-display-prompt'],
            capture_output=True, text=True, timeout=30,
            cwd=SCRIPT_DIR
        )
        if result.returncode != 0:
            print(f"错误: 模型加载失败:\n{result.stderr}")
            return False

        self.llama_ready = True
        print("模型就绪")
        return True

    def get_prompt(self, text, source_lang="auto", target_lang=None):
        """生成翻译提示词"""
        if target_lang is None:
            target_lang = self.target_lang

        target_lang_name = LANGUAGES.get(target_lang, target_lang)
        is_chinese_source = any('\u4e00' <= c <= '\u9fff' for c in text)

        if is_chinese_source:
            if target_lang_name == "Chinese":
                target_lang_name = "English"
            prompt = f"将以下文本翻译为{target_lang_name}，注意只需要输出翻译后的结果，不要额外解释：\n\n{text}"
        else:
            if target_lang_name == "Chinese":
                prompt = f"将以下文本翻译为中文，注意只需要输出翻译后的结果，不要额外解释：\n\n{text}"
            else:
                prompt = f"Translate the following segment into {target_lang_name}, without additional explanation.\n\n{text}"

        return prompt

    def translate(self, text, source_lang="auto", target_lang=None):
        """执行翻译"""
        if not self.llama_ready:
            return "错误: 模型未就绪"

        if not text.strip():
            return ""

        prompt = self.get_prompt(text, source_lang, target_lang)
        model_path = self.resolve_path(self.config["model_path"])

        try:
            result = subprocess.run(
                [
                    self.config["llama_cli_path"],
                    '-m', model_path,
                    '-p', prompt,
                    '-n', str(self.config["max_tokens"]),
                    '--temp', str(self.config["temperature"]),
                    '-t', str(self.config["n_threads"]),
                    '-c', str(self.config["n_ctx"]),
                    '--top-k', str(self.config["top_k"]),
                    '--top-p', str(self.config["top_p"]),
                    '--repeat-penalty', str(self.config["repetition_penalty"]),
                    '--no-display-prompt',
                ],
                capture_output=True, text=True,
                timeout=120,
                cwd=SCRIPT_DIR
            )

            if result.returncode != 0:
                return f"翻译错误: {result.stderr.strip()}"

            translation = result.stdout.strip()

            # 清理停止标记
            for stop in STOP_TOKENS:
                translation = translation.replace(stop, "")

            return translation.strip()

        except subprocess.TimeoutExpired:
            return "翻译超时"
        except Exception as e:
            return f"翻译错误: {e}"

    def get_clipboard(self):
        """获取剪贴板内容"""
        try:
            result = subprocess.run(
                ['xclip', '-selection', 'clipboard', '-o'],
                capture_output=True, text=True, timeout=1
            )
            return result.stdout
        except:
            return ""

    def monitor_clipboard(self):
        """监控剪贴板变化"""
        print("开始监控剪贴板...")
        print("复制文本后将自动翻译")
        print("按 Ctrl+C 退出")

        while True:
            try:
                current = self.get_clipboard()
                if current and current != self.last_clipboard:
                    self.last_clipboard = current
                    print(f"\n原文: {current}")
                    translation = self.translate(current)
                    print(f"译文: {translation}")
                time.sleep(self.config["clipboard_poll_interval"])
            except KeyboardInterrupt:
                print("\n停止监控")
                break

    def interactive_mode(self):
        """交互模式"""
        print("\n=== Qubes Translation Qube ===")
        print("输入文本进行翻译，输入 /help 查看帮助")
        print("输入 /quit 退出\n")

        while True:
            try:
                text = input("> ").strip()
                if not text:
                    continue
                if text.startswith('/'):
                    self.handle_command(text)
                    continue
                translation = self.translate(text)
                print(translation)
            except KeyboardInterrupt:
                print("\n再见！")
                break
            except EOFError:
                print("\n再见！")
                break

    def handle_command(self, command):
        """处理命令"""
        cmd = command.lower().split()

        if cmd[0] in ('/quit', '/exit'):
            print("再见！")
            sys.exit(0)

        elif cmd[0] == '/help':
            print("\n可用命令:")
            print("  /lang <src> <tgt>  - 设置语言方向 (如 /lang zh en)")
            print("  /languages         - 显示支持的语言")
            print("  /clipboard         - 开始剪贴板监控")
            print("  /config            - 显示当前配置")
            print("  /help              - 显示帮助")
            print("  /quit              - 退出\n")

        elif cmd[0] == '/languages':
            print("\n支持的语言:")
            for code, name in sorted(LANGUAGES.items()):
                print(f"  {code:8} - {name}")
            print()

        elif cmd[0] == '/lang':
            if len(cmd) == 3:
                src, tgt = cmd[1], cmd[2]
                if src in LANGUAGES and tgt in LANGUAGES:
                    self.source_lang = src
                    self.target_lang = LANGUAGES[tgt]
                    print(f"语言设置: {LANGUAGES[src]} -> {LANGUAGES[tgt]}")
                else:
                    print("错误: 不支持的语言代码")
            else:
                print("用法: /lang <源语言代码> <目标语言代码>")

        elif cmd[0] == '/clipboard':
            self.monitor_clipboard()

        elif cmd[0] == '/config':
            print("\n当前配置:")
            for key, value in self.config.items():
                print(f"  {key}: {value}")
            print(f"  源语言: {self.source_lang}")
            print(f"  目标语言: {self.target_lang}")
            print()

        else:
            print(f"未知命令: {cmd[0]}")


def main():
    import argparse

    parser = argparse.ArgumentParser(description='Qubes Translation Qube')
    parser.add_argument('--clipboard', '-c', action='store_true',
                        help='启动剪贴板监控模式')
    parser.add_argument('--config', default='config.json',
                        help='配置文件路径')
    parser.add_argument('--source-lang', '-s', default=None,
                        help='源语言代码')
    parser.add_argument('--target-lang', '-t', default=None,
                        help='目标语言代码')
    parser.add_argument('--text', default=None,
                        help='要翻译的文本')

    args = parser.parse_args()

    service = TranslationService(args.config)

    if not service.load_model():
        sys.exit(1)

    if args.source_lang:
        service.source_lang = args.source_lang
    if args.target_lang:
        service.target_lang = LANGUAGES.get(args.target_lang, args.target_lang)

    if args.text:
        translation = service.translate(args.text)
        print(translation)
        return

    if args.clipboard:
        service.monitor_clipboard()
        return

    service.interactive_mode()


if __name__ == "__main__":
    main()
PYEOF

    chmod +x "$SCRIPT_DIR/translate.py"
    info "翻译脚本创建完成"
}

# ── 创建配置文件 ───────────────────────────────────
create_config() {
    info "创建配置文件..."

    cat > "$SCRIPT_DIR/config.json" << 'JSONEOF'
{
  "model_path": "models/Hy-MT1.5-1.8B-1.25bit.gguf",
  "llama_cli_path": "./llama-cli",
  "default_source_lang": "auto",
  "default_target_lang": "English",
  "clipboard_poll_interval": 0.5,
  "max_tokens": 512,
  "temperature": 0.7,
  "top_k": 20,
  "top_p": 0.6,
  "repetition_penalty": 1.05,
  "n_threads": 4,
  "n_ctx": 2048
}
JSONEOF

    info "配置文件创建完成"
}

# ── 剪贴板工具 ─────────────────────────────────────
setup_clipboard() {
    info "检查剪贴板工具..."
    if ! command -v xclip &> /dev/null; then
        warn "xclip 未安装，正在安装..."
        sudo apt-get install -y -qq xclip > /dev/null 2>&1
    fi
    info "剪贴板工具就绪"
}

# ── 安装摘要 ───────────────────────────────────────
show_summary() {
    local llama_cli="$SCRIPT_DIR/llama-cli"
    if [ -f "$llama_cli" ]; then
        local version=$("$llama_cli" --version 2>&1 | head -1 || echo "unknown")
    else
        local version="未编译（运行 ./install.sh 安装）"
    fi

    echo ""
    echo "=========================================="
    echo "  Qubes Translation Qube 安装完成"
    echo "=========================================="
    echo ""
    echo "  llama.cpp: $version"
    echo ""
    echo "使用方法："
    echo "  ./translate.sh                      - 交互模式"
    echo "  ./translate.sh --text '你好'        - 单次翻译"
    echo "  ./translate.sh --clipboard          - 剪贴板监控"
    echo "  ./install.sh --download-model       - 下载模型"
    echo ""
    echo "配置文件: config.json"
    echo "模型目录: models/"
    echo "=========================================="
}

# ── 主流程 ─────────────────────────────────────────
main() {
    echo ""
    echo "=========================================="
    echo "  Qubes Translation Qube 安装程序"
    echo "=========================================="
    echo ""

    local download_model_flag=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            --download-model)
                download_model_flag=true
                shift
                ;;
            *)
                warn "未知参数: $1"
                shift
                ;;
        esac
    done

    check_qubes
    check_requirements
    install_dependencies
    build_llama_cpp
    install_python_deps
    create_translate_script
    create_config
    setup_clipboard

    # 创建启动脚本
    cat > "$SCRIPT_DIR/translate.sh" << 'SHEOF'
#!/bin/bash
cd "$(dirname "$0")"
exec python3 translate.py "$@"
SHEOF
    chmod +x "$SCRIPT_DIR/translate.sh"

    if [ "$download_model_flag" = true ]; then
        download_model
    else
        echo ""
        info "跳过模型下载。稍后运行: ./install.sh --download-model"
    fi

    show_summary
}

main "$@"
