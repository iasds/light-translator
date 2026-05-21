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
    info "检查 Python 依赖..."

    # translate.py 只使用 Python 标准库，无需 pip 安装
    # 如需 requests（模型下载备用），通过 apt 安装
    if ! python3 -c "import requests" 2>/dev/null; then
        sudo apt-get install -y -qq python3-requests 2>/dev/null || true
    fi

    info "Python 依赖就绪"
}

# ── 下载模型 ───────────────────────────────────────
download_model() {
    info "下载翻译模型..."

    mkdir -p "$SCRIPT_DIR/models"

    local model_file="Hy-MT1.5-1.8B-Q4_K_M.gguf"
    local model_path="$SCRIPT_DIR/models/$model_file"

    if [ -f "$model_path" ]; then
        local file_size=$(stat -c%s "$model_path" 2>/dev/null || echo 0)
        if [ "$file_size" -gt 500000000 ]; then
            warn "模型文件已存在（${file_size} 字节），跳过下载"
            return 0
        fi
        warn "已存在的模型文件异常（${file_size} 字节），重新下载"
        rm -f "$model_path"
    fi

    info "下载模型文件（约 1.1GB，Q4_K_M 量化）..."
    info "首次翻译需 ~45s 加载模型，后续从缓存加载约 4s"

    # 安装 git-lfs（HF 使用 Git LFS 存储大文件，直接 curl 只能拿到指针）
    if ! command -v git-lfs &> /dev/null; then
        info "安装 git-lfs..."
        sudo apt-get install -y -qq git-lfs > /dev/null 2>&1 || true
        git lfs install --skip-repo 2>/dev/null || true
    fi

    # 用 git clone 单个文件（sparse checkout + LFS）
    local tmp_dir=$(mktemp -d)
    cd "$tmp_dir"
    info "从 HuggingFace 拉取模型..."

    git init -q
    git remote add origin https://huggingface.co/tencent/HY-MT1.5-1.8B-GGUF
    git config core.sparseCheckout true
    echo "$model_file" > .git/info/sparse-checkout
    git lfs pull origin main --include="$model_file" 2>/dev/null || {
        # 回退：直接用 git lfs 拉取（不 sparse checkout）
        GIT_LFS_SKIP_SMUDGE=1 git pull origin main --depth 1 2>/dev/null
        git lfs pull --include="$model_file" 2>/dev/null
    }

    if [ -f "$model_file" ]; then
        local fs=$(stat -c%s "$model_file" 2>/dev/null || echo 0)
        if [ "$fs" -gt 500000000 ]; then
            mv "$model_file" "$model_path"
            cd "$SCRIPT_DIR"
            rm -rf "$tmp_dir"
            info "模型下载完成（${fs} 字节）"
            return 0
        fi
    fi

    cd "$SCRIPT_DIR"
    rm -rf "$tmp_dir"

    # 最终回退：尝试 wget 镜像
    warn "git-lfs 下载失败，尝试直接下载..."
    if curl -L --connect-timeout 30 --max-time 600 -o "$model_path" \
        "https://hf-mirror.com/tencent/HY-MT1.5-1.8B-GGUF/resolve/main/HY-MT1.5-1.8B-Q4_K_M.gguf" 2>&1; then
        local fs=$(stat -c%s "$model_path" 2>/dev/null || echo 0)
        if [ "$fs" -gt 500000000 ]; then
            info "模型下载完成（${fs} 字节）"
            return 0
        fi
    fi

    error "模型下载失败。请手动从以下地址下载模型文件（约 1.1GB）放到 $SCRIPT_DIR/models/ ：\n  https://huggingface.co/tencent/HY-MT1.5-1.8B-GGUF\n  或使用 huggingface-cli: pip install huggingface_hub && huggingface-cli download tencent/HY-MT1.5-1.8B-GGUF Hy-MT1.5-1.8B-Q4_K_M.gguf --local-dir models/"
}

# ── 创建翻译脚本 ───────────────────────────────────
create_translate_script() {
    info "创建翻译脚本..."

    local translate_py="$SCRIPT_DIR/translate.py"

    # 如果本地仓库已有 translate.py，直接复制；否则从 GitHub 下载
    local source_py="$(dirname "$0")/translate.py"
    if [ -f "$source_py" ] && [ "$source_py" != "$translate_py" ]; then
        cp "$source_py" "$translate_py"
    else
        info "从 GitHub 下载 translate.py..."
        curl -sSL "https://raw.githubusercontent.com/iasds/qubes-translation-qube/main/translate.py" -o "$translate_py" || {
            warn "下载失败，使用内置版本"
            generate_translate_py > "$translate_py"
        }
    fi

    chmod +x "$translate_py"
    info "翻译脚本就绪"
}

# ── 备用：生成内置 translate.py ────────────────────
generate_translate_py() {
    cat << 'PYEOF'
#!/usr/bin/env python3
"""
Qubes Translation Qube - 翻译服务
基于腾讯混元 HY-MT1.5 翻译模型，使用 llama-cli 推理
"""
import os, sys, json, time, subprocess

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DEFAULT_CONFIG = {
    "model_path": "models/Hy-MT1.5-1.8B-Q4_K_M.gguf",
    "llama_cli_path": "./llama-cli",
    "default_source_lang": "auto", "default_target_lang": "English",
    "clipboard_poll_interval": 0.5, "max_tokens": 256,
    "temperature": 0.7, "top_k": 20, "top_p": 0.6,
    "repetition_penalty": 1.05, "n_threads": 2, "n_ctx": 512,
}
LANGUAGES = {"zh":"Chinese","en":"English","fr":"French","ja":"Japanese","ko":"Korean","de":"German","es":"Spanish","ru":"Russian","ar":"Arabic","pt":"Portuguese","it":"Italian","th":"Thai","vi":"Vietnamese","id":"Indonesian","ms":"Malay","tl":"Filipino","hi":"Hindi","pl":"Polish","cs":"Czech","nl":"Dutch","km":"Khmer","my":"Burmese","fa":"Persian","gu":"Gujarati","ur":"Urdu","te":"Telugu","mr":"Marathi","he":"Hebrew","bn":"Bengali","ta":"Tamil","uk":"Ukrainian","bo":"Tibetan","kk":"Kazakh","mn":"Mongolian","ug":"Uyghur","yue":"Cantonese","zh-Hant":"Traditional Chinese"}
STOP_TOKENS = ["<｜hy_end▁of▁sentence｜>","<｜hy_EOT｜>"]

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
                config.update(json.load(f))
        return config
    def resolve_path(self, path):
        if os.path.isabs(path): return path
        return os.path.join(SCRIPT_DIR, path)
    def load_model(self):
        llama_cli = self.resolve_path(self.config["llama_cli_path"])
        model_path = self.resolve_path(self.config["model_path"])
        if not os.path.exists(model_path):
            print(f"错误: 模型文件不存在: {model_path}")
            print("请运行 ./install.sh --download-model 下载模型")
            return False
        if not os.path.exists(llama_cli):
            r = subprocess.run(['which','llama-cli'], capture_output=True, text=True)
            if r.returncode == 0: self.config["llama_cli_path"] = r.stdout.strip()
            else:
                print(f"错误: llama-cli 未找到")
                print("请运行 ./install.sh 编译 llama.cpp")
                return False
        print("正在验证模型...")
        r = subprocess.run(
            [self.config["llama_cli_path"],'-m',model_path,'-p','hello','-n','1','-c','64',
             '--no-display-prompt','--single-turn','--simple-io'],
            capture_output=True, text=True, timeout=120, cwd=SCRIPT_DIR)
        if r.returncode != 0:
            print(f"错误: 模型加载失败:\n{r.stderr}")
            return False
        self.llama_ready = True
        print("模型就绪")
        return True
    def get_prompt(self, text, source_lang="auto", target_lang=None):
        if target_lang is None: target_lang = self.target_lang
        target_lang_name = LANGUAGES.get(target_lang, target_lang)
        is_cn = any('\u4e00'<=c<='\u9fff' for c in text)
        if is_cn:
            if target_lang_name == "Chinese": target_lang_name = "English"
            return f"将以下文本翻译为{target_lang_name}，注意只需要输出翻译后的结果，不要额外解释：\n\n{text}"
        else:
            if target_lang_name == "Chinese":
                return f"将以下文本翻译为中文，注意只需要输出翻译后的结果，不要额外解释：\n\n{text}"
            return f"Translate the following segment into {target_lang_name}, without additional explanation.\n\n{text}"
    def translate(self, text, source_lang="auto", target_lang=None):
        if not self.llama_ready: return "错误: 模型未就绪"
        if not text.strip(): return ""
        prompt = self.get_prompt(text, source_lang, target_lang)
        model_path = self.resolve_path(self.config["model_path"])
        try:
            r = subprocess.run(
                [self.config["llama_cli_path"],'-m',model_path,'-p',prompt,
                 '-n',str(self.config["max_tokens"]),'--temp',str(self.config["temperature"]),
                 '-t',str(self.config["n_threads"]),'-c',str(self.config["n_ctx"]),
                 '--top-k',str(self.config["top_k"]),'--top-p',str(self.config["top_p"]),
                 '--repeat-penalty',str(self.config["repetition_penalty"]),
                 '--no-display-prompt','--single-turn','--simple-io'],
                capture_output=True, text=True, timeout=120, cwd=SCRIPT_DIR)
            if r.returncode != 0: return f"翻译错误: {r.stderr.strip()}"
            out = r.stdout.strip()
            result_lines = []
            for line in reversed(out.split('\n')):
                if line.startswith('[ Prompt:') or line.startswith('Exiting'): break
                s = line.strip()
                if s and not s.startswith('>') and not s.startswith('build') and not s.startswith('model') and not s.startswith('modalities') and not s.startswith('available') and not s.startswith('/') and not s.startswith('Loading'):
                    result_lines.insert(0, s)
            for stop in STOP_TOKENS: out = '\n'.join(result_lines).replace(stop, "")
            return out.strip()
        except subprocess.TimeoutExpired: return "翻译超时"
        except Exception as e: return f"翻译错误: {e}"
    def get_clipboard(self):
        try:
            r = subprocess.run(['xclip','-selection','clipboard','-o'], capture_output=True, text=True, timeout=1)
            return r.stdout
        except: return ""
    def monitor_clipboard(self):
        print("开始监控剪贴板...\n复制文本后将自动翻译\n按 Ctrl+C 退出")
        while True:
            try:
                cur = self.get_clipboard()
                if cur and cur != self.last_clipboard:
                    self.last_clipboard = cur
                    print(f"\n原文: {cur}")
                    print(f"译文: {self.translate(cur)}")
                time.sleep(self.config["clipboard_poll_interval"])
            except KeyboardInterrupt:
                print("\n停止监控"); break
    def interactive_mode(self):
        print("\n=== Qubes Translation Qube ===")
        print("输入文本进行翻译，/help 查看帮助，/quit 退出\n")
        while True:
            try:
                text = input("> ").strip()
                if not text: continue
                if text.startswith('/'): self.handle_command(text); continue
                print(self.translate(text))
            except (KeyboardInterrupt, EOFError): print("\n再见！"); break
    def handle_command(self, command):
        cmd = command.lower().split()
        if cmd[0] in ('/quit','/exit'): print("再见！"); sys.exit(0)
        elif cmd[0] == '/help':
            print("\n  /lang <src> <tgt> - 设置语言方向\n  /languages - 支持的语言\n  /clipboard - 剪贴板监控\n  /config - 当前配置\n  /quit - 退出\n")
        elif cmd[0] == '/languages':
            for c,n in sorted(LANGUAGES.items()): print(f"  {c:8} - {n}")
        elif cmd[0] == '/lang':
            if len(cmd)==3 and cmd[1] in LANGUAGES and cmd[2] in LANGUAGES:
                self.source_lang=cmd[1]; self.target_lang=LANGUAGES[cmd[2]]
                print(f"语言: {LANGUAGES[cmd[1]]} -> {LANGUAGES[cmd[2]]}")
            else: print("用法: /lang <源> <目标>")
        elif cmd[0] == '/clipboard': self.monitor_clipboard()
        elif cmd[0] == '/config':
            for k,v in self.config.items(): print(f"  {k}: {v}")
        else: print(f"未知命令: {cmd[0]}")

def main():
    import argparse
    p = argparse.ArgumentParser(description='Qubes Translation Qube')
    p.add_argument('--clipboard','-c',action='store_true',help='剪贴板监控')
    p.add_argument('--config',default='config.json',help='配置文件路径')
    p.add_argument('--source-lang','-s',default=None,help='源语言')
    p.add_argument('--target-lang','-t',default=None,help='目标语言')
    p.add_argument('--text',default=None,help='翻译文本')
    a = p.parse_args()
    s = TranslationService(a.config)
    if not s.load_model(): sys.exit(1)
    if a.source_lang: s.source_lang = a.source_lang
    if a.target_lang: s.target_lang = LANGUAGES.get(a.target_lang, a.target_lang)
    if a.text: print(s.translate(a.text)); return
    if a.clipboard: s.monitor_clipboard(); return
    s.interactive_mode()

if __name__=="__main__": main()
PYEOF
}

# ── 创建配置文件 ───────────────────────────────────
create_config() {
    info "创建配置文件..."

    cat > "$SCRIPT_DIR/config.json" << 'JSONEOF'
{
  "model_path": "models/Hy-MT1.5-1.8B-Q4_K_M.gguf",
  "llama_cli_path": "./llama-cli",
  "default_source_lang": "auto",
  "default_target_lang": "English",
  "clipboard_poll_interval": 0.5,
  "max_tokens": 256,
  "temperature": 0.7,
  "top_k": 20,
  "top_p": 0.6,
  "repetition_penalty": 1.05,
  "n_threads": 2,
  "n_ctx": 512
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
    echo "  ./webui.sh                          - Web 界面 (http://IP:8080)"
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

    cat > "$SCRIPT_DIR/webui.sh" << 'SHEOF'
#!/bin/bash
cd "$(dirname "$0")"
exec python3 webui.py
SHEOF
    chmod +x "$SCRIPT_DIR/webui.sh"

    if [ "$download_model_flag" = true ]; then
        download_model
    else
        echo ""
        info "跳过模型下载。稍后运行: ./install.sh --download-model"
    fi

    show_summary
}

main "$@"
