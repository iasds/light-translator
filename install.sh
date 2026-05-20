#!/bin/bash
# Qubes Translation Qube - 一键安装脚本
# 用法: ./install.sh [--download-model] [--gpu vulkan]

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 打印带颜色的消息
info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# 检查是否在 Qubes OS 中
check_qubes() {
    if [ -f /etc/qubes-release ]; then
        info "检测到 Qubes OS 环境"
    else
        warn "未检测到 Qubes OS，某些功能可能不可用"
    fi
}

# 检查系统要求
check_requirements() {
    info "检查系统要求..."
    
    # 检查内存
    local mem_mb=$(free -m | awk '/^Mem:/{print $2}')
    if [ "$mem_mb" -lt 1800 ]; then
        warn "系统内存 ${mem_mb}MB，建议至少 2GB"
    else
        info "内存检查通过: ${mem_mb}MB"
    fi
    
    # 检查磁盘空间
    local disk_gb=$(df -BG . | awk 'NR==2{print $4}' | sed 's/G//')
    if [ "$disk_gb" -lt 3 ]; then
        error "磁盘空间不足，需要至少 3GB，当前可用 ${disk_gb}GB"
    else
        info "磁盘空间检查通过: ${disk_gb}GB 可用"
    fi
}

# 安装系统依赖
install_dependencies() {
    info "安装系统依赖..."
    
    sudo apt-get update -qq
    sudo apt-get install -y -qq \
        python3 \
        python3-pip \
        python3-venv \
        curl \
        wget \
        git \
        xclip \
        build-essential \
        cmake \
        > /dev/null 2>&1
    
    info "系统依赖安装完成"
}

# 创建虚拟环境
setup_venv() {
    info "创建 Python 虚拟环境..."
    
    if [ -d "venv" ]; then
        warn "虚拟环境已存在，跳过创建"
    else
        python3 -m venv venv
        info "虚拟环境创建完成"
    fi
    
    # 激活虚拟环境
    source venv/bin/activate
    
    # 升级 pip
    pip install --upgrade pip -q
}

# 安装 Python 依赖
install_python_deps() {
    info "安装 Python 依赖..."
    
    # 创建 requirements.txt
    cat > requirements.txt << 'EOF'
llama-cpp-python>=0.2.0
EOF
    
    # 安装依赖
    pip install -r requirements.txt -q
    
    info "Python 依赖安装完成"
}

# 下载模型
download_model() {
    info "下载翻译模型..."
    
    mkdir -p models
    
    local model_url="https://huggingface.co/AngelSlim/Hy-MT1.5-1.8B-1.25bit-GGUF/resolve/main/Hy-MT1.5-1.8B-1.25bit-Q4_K_M.gguf"
    local model_path="models/Hy-MT1.5-1.8B-1.25bit-Q4_K_M.gguf"
    
    if [ -f "$model_path" ]; then
        warn "模型文件已存在，跳过下载"
        return 0
    fi
    
    info "下载模型文件（约 440MB）..."
    wget -q --show-progress -O "$model_path" "$model_url" || {
        error "模型下载失败，请检查网络连接"
    }
    
    info "模型下载完成"
}

# 创建翻译脚本
create_translate_script() {
    info "创建翻译脚本..."
    
    cat > translate.py << 'PYEOF'
#!/usr/bin/env python3
"""
Qubes Translation Qube - 翻译服务
基于腾讯混元 HY-MT1.5 翻译模型
"""

import os
import sys
import json
import time
import subprocess
import threading
from pathlib import Path

# 默认配置
DEFAULT_CONFIG = {
    "model_path": "models/Hy-MT1.5-1.8B-1.25bit-Q4_K_M.gguf",
    "default_source_lang": "auto",
    "default_target_lang": "English",
    "clipboard_poll_interval": 0.5,
    "max_tokens": 512,
    "temperature": 0.7,
    "top_k": 20,
    "top_p": 0.6,
    "repetition_penalty": 1.05
}

# 支持的语言
LANGUAGES = {
    "zh": "Chinese",
    "en": "English",
    "fr": "French",
    "ja": "Japanese",
    "ko": "Korean",
    "de": "German",
    "es": "Spanish",
    "ru": "Russian",
    "ar": "Arabic",
    "pt": "Portuguese",
    "it": "Italian",
    "th": "Thai",
    "vi": "Vietnamese",
    "id": "Indonesian",
    "ms": "Malay",
    "tl": "Filipino",
    "hi": "Hindi",
    "pl": "Polish",
    "cs": "Czech",
    "nl": "Dutch",
    "km": "Khmer",
    "my": "Burmese",
    "fa": "Persian",
    "gu": "Gujarati",
    "ur": "Urdu",
    "te": "Telugu",
    "mr": "Marathi",
    "he": "Hebrew",
    "bn": "Bengali",
    "ta": "Tamil",
    "uk": "Ukrainian",
    "bo": "Tibetan",
    "kk": "Kazakh",
    "mn": "Mongolian",
    "ug": "Uyghur",
    "yue": "Cantonese",
    "zh-Hant": "Traditional Chinese"
}

class TranslationService:
    def __init__(self, config_path="config.json"):
        self.config = self.load_config(config_path)
        self.model = None
        self.source_lang = self.config["default_source_lang"]
        self.target_lang = self.config["default_target_lang"]
        self.last_clipboard = ""
        
    def load_config(self, config_path):
        """加载配置文件"""
        config = DEFAULT_CONFIG.copy()
        if os.path.exists(config_path):
            with open(config_path, 'r', encoding='utf-8') as f:
                user_config = json.load(f)
                config.update(user_config)
        return config
    
    def load_model(self):
        """加载翻译模型"""
        try:
            from llama_cpp import Llama
            
            model_path = self.config["model_path"]
            if not os.path.exists(model_path):
                print(f"错误: 模型文件不存在: {model_path}")
                print("请运行 ./install.sh --download-model 下载模型")
                return False
            
            print("正在加载模型...")
            self.model = Llama(
                model_path=model_path,
                n_ctx=2048,
                n_threads=4,
                verbose=False
            )
            print("模型加载完成")
            return True
            
        except ImportError:
            print("错误: 缺少 llama-cpp-python 依赖")
            print("请运行: pip install llama-cpp-python")
            return False
        except Exception as e:
            print(f"错误: 模型加载失败: {e}")
            return False
    
    def get_prompt(self, text, source_lang="auto", target_lang=None):
        """生成翻译提示词"""
        if target_lang is None:
            target_lang = self.target_lang
        
        # 获取目标语言的中文名称
        target_lang_name = LANGUAGES.get(target_lang, target_lang)
        
        # 检测源语言是否为中文
        is_chinese_source = any('\u4e00' <= c <= '\u9fff' for c in text)
        
        if is_chinese_source:
            # 中译外
            if target_lang_name == "Chinese":
                target_lang_name = "English"
            prompt = f"将以下文本翻译为{target_lang_name}，注意只需要输出翻译后的结果，不要额外解释：\n\n{text}"
        else:
            # 外译中或外译外
            if target_lang_name == "Chinese":
                prompt = f"将以下文本翻译为中文，注意只需要输出翻译后的结果，不要额外解释：\n\n{text}"
            else:
                prompt = f"Translate the following segment into {target_lang_name}, without additional explanation.\n\n{text}"
        
        return prompt
    
    def translate(self, text, source_lang="auto", target_lang=None):
        """执行翻译"""
        if not self.model:
            return "错误: 模型未加载"
        
        if not text.strip():
            return ""
        
        prompt = self.get_prompt(text, source_lang, target_lang)
        
        try:
            output = self.model(
                prompt,
                max_tokens=self.config["max_tokens"],
                temperature=self.config["temperature"],
                top_k=self.config["top_k"],
                top_p=self.config["top_p"],
                repeat_penalty=self.config["repetition_penalty"],
                stop=["<｜hy_end▁of▁sentence｜>", "<｜hy_EOT｜>"],
                echo=False
            )
            
            translation = output["choices"][0]["text"].strip()
            return translation
            
        except Exception as e:
            return f"翻译错误: {e}"
    
    def get_clipboard(self):
        """获取剪贴板内容"""
        try:
            result = subprocess.run(
                ['xclip', '-selection', 'clipboard', '-o'],
                capture_output=True,
                text=True,
                timeout=1
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
                
                # 处理命令
                if text.startswith('/'):
                    self.handle_command(text)
                    continue
                
                # 翻译
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
        
        if cmd[0] == '/quit' or cmd[0] == '/exit':
            print("再见！")
            sys.exit(0)
        
        elif cmd[0] == '/help':
            print("\n可用命令:")
            print("  /lang <源语言> <目标语言>  - 设置语言方向")
            print("  /lang zh en               - 中译英")
            print("  /lang en zh               - 英译中")
            print("  /languages                - 显示支持的语言")
            print("  /clipboard                - 开始剪贴板监控")
            print("  /config                   - 显示当前配置")
            print("  /help                     - 显示帮助")
            print("  /quit                     - 退出")
            print()
        
        elif cmd[0] == '/languages':
            print("\n支持的语言:")
            for code, name in sorted(LANGUAGES.items()):
                print(f"  {code:8} - {name}")
            print()
        
        elif cmd[0] == '/lang':
            if len(cmd) == 3:
                src = cmd[1]
                tgt = cmd[2]
                if src in LANGUAGES and tgt in LANGUAGES:
                    self.source_lang = src
                    self.target_lang = LANGUAGES[tgt]
                    print(f"语言设置: {LANGUAGES[src]} -> {LANGUAGES[tgt]}")
                else:
                    print("错误: 不支持的语言代码，输入 /languages 查看支持的语言")
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
            print(f"未知命令: {cmd[0]}，输入 /help 查看帮助")


def main():
    """主函数"""
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
    
    # 创建翻译服务
    service = TranslationService(args.config)
    
    # 加载模型
    if not service.load_model():
        sys.exit(1)
    
    # 设置语言
    if args.source_lang:
        service.source_lang = args.source_lang
    if args.target_lang:
        service.target_lang = LANGUAGES.get(args.target_lang, args.target_lang)
    
    # 单次翻译模式
    if args.text:
        translation = service.translate(args.text)
        print(translation)
        return
    
    # 剪贴板监控模式
    if args.clipboard:
        service.monitor_clipboard()
        return
    
    # 交互模式
    service.interactive_mode()


if __name__ == "__main__":
    main()
PYEOF
    
    chmod +x translate.py
    info "翻译脚本创建完成"
}

# 创建启动脚本
create_launcher() {
    info "创建启动脚本..."
    
    cat > translate.sh << 'SHEOF'
#!/bin/bash
# Qubes Translation Qube 启动脚本

cd "$(dirname "$0")"

# 激活虚拟环境
source venv/bin/activate

# 运行翻译服务
python3 translate.py "$@"
SHEOF
    
    chmod +x translate.sh
    info "启动脚本创建完成"
}

# 创建配置文件
create_config() {
    info "创建配置文件..."
    
    cat > config.json << 'JSONEOF'
{
  "model_path": "models/Hy-MT1.5-1.8B-1.25bit-Q4_K_M.gguf",
  "default_source_lang": "auto",
  "default_target_lang": "English",
  "clipboard_poll_interval": 0.5,
  "max_tokens": 512,
  "temperature": 0.7,
  "top_k": 20,
  "top_p": 0.6,
  "repetition_penalty": 1.05
}
JSONEOF
    
    info "配置文件创建完成"
}

# 配置剪贴板权限
setup_clipboard() {
    info "配置剪贴板权限..."
    
    # 检查 xclip 是否可用
    if ! command -v xclip &> /dev/null; then
        warn "xclip 未安装，正在安装..."
        sudo apt-get install -y -qq xclip > /dev/null 2>&1
    fi
    
    info "剪贴板配置完成"
}

# 显示安装摘要
show_summary() {
    echo ""
    echo "=========================================="
    echo "  安装完成！"
    echo "=========================================="
    echo ""
    echo "使用方法："
    echo "  1. 启动翻译服务: ./translate.sh"
    echo "  2. 交互模式: 输入文本直接翻译"
    echo "  3. 剪贴板模式: /clipboard 开始监控"
    echo "  4. 查看帮助: /help"
    echo ""
    echo "配置文件: config.json"
    echo "模型目录: models/"
    echo ""
    echo "=========================================="
}

# 主函数
main() {
    echo ""
    echo "=========================================="
    echo "  Qubes Translation Qube 安装程序"
    echo "=========================================="
    echo ""
    
    # 解析参数
    local download_model=false
    local gpu_support=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --download-model)
                download_model=true
                shift
                ;;
            --gpu)
                gpu_support="$2"
                shift 2
                ;;
            *)
                warn "未知参数: $1"
                shift
                ;;
        esac
    done
    
    # 执行安装步骤
    check_qubes
    check_requirements
    install_dependencies
    setup_venv
    install_python_deps
    create_translate_script
    create_launcher
    create_config
    setup_clipboard
    
    # 下载模型
    if [ "$download_model" = true ]; then
        download_model
    else
        echo ""
        info "跳过模型下载"
        info "稍后运行 ./install.sh --download-model 下载模型"
    fi
    
    show_summary
}

# 运行主函数
main "$@"
