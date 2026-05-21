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
    "model_path": "models/Hy-MT1.5-1.8B-Q4_K_M.gguf",
    "llama_cli_path": "./llama-cli",
    "default_source_lang": "auto",
    "default_target_lang": "English",
    "max_tokens": 256,
    "temperature": 0.1,
    "top_k": 5,
    "top_p": 0.4,
    "repetition_penalty": 1.05,
    "n_threads": 2,
    "n_ctx": 512,
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

# 中文语言名（用于中文 prompt 模板）
LANG_NAMES_ZH = {
    "Chinese": "中文", "English": "英文", "French": "法文",
    "Japanese": "日文", "Korean": "韩文", "German": "德文",
    "Spanish": "西班牙文", "Russian": "俄文", "Arabic": "阿拉伯文",
    "Portuguese": "葡萄牙文", "Italian": "意大利文", "Thai": "泰文",
    "Vietnamese": "越南文", "Indonesian": "印尼文", "Malay": "马来文",
    "Filipino": "菲律宾文", "Hindi": "印地文", "Polish": "波兰文",
    "Czech": "捷克文", "Dutch": "荷兰文", "Khmer": "高棉文",
    "Burmese": "缅甸文", "Persian": "波斯文", "Gujarati": "古吉拉特文",
    "Urdu": "乌尔都文", "Telugu": "泰卢固文", "Marathi": "马拉地文",
    "Hebrew": "希伯来文", "Bengali": "孟加拉文", "Tamil": "泰米尔文",
    "Ukrainian": "乌克兰文", "Tibetan": "藏文", "Kazakh": "哈萨克文",
    "Mongolian": "蒙古文", "Uyghur": "维吾尔文", "Cantonese": "广东话",
    "Traditional Chinese": "繁体中文",
}

# 模型停止标记
STOP_TOKENS = ["<｜hy_end▁of▁sentence｜>", "<｜hy_EOT｜>"]


class TranslationService:
    def __init__(self, config_path="config.json"):
        self.config = self.load_config(config_path)
        self.source_lang = self.config["default_source_lang"]
        self.target_lang = self.config["default_target_lang"]
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
             '--no-display-prompt', '--single-turn',
             '--simple-io'],
            capture_output=True, text=True, timeout=120,
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
            # 中文 prompt 里用中文语言名（"英文" 而非 "English"）
            target_name_zh = LANG_NAMES_ZH.get(target_lang_name, target_lang_name)
            prompt = f"将以下文本翻译为{target_name_zh}，注意只需要输出翻译后的结果，不要额外解释：\n\n{text}"
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
                    '--single-turn',
                    '--simple-io',
                ],
                capture_output=True, text=True,
                timeout=120,
                cwd=SCRIPT_DIR
            )

            if result.returncode != 0:
                return f"翻译错误: {result.stderr.strip()}"

            translation = result.stdout.strip()

            # 提取实际的翻译文本（跳过 llama-cli banner 和 prompt 回显）
            # llama-cli 输出格式（从后往前）：
            #   [ Prompt: ...] / Exiting... (跳过)
            #   译文行
            #   (空行)
            #   原文行
            #   > prompt回显 (遇此停止，前面是原文)
            lines = translation.split('\n')
            result_lines = []
            for line in reversed(lines):
                stripped = line.strip()
                if stripped.startswith('[ Prompt:') or stripped.startswith('[ ') or stripped.startswith('Prompt:'):
                    continue
                if stripped.startswith('Exiting') or stripped.startswith('build ') or stripped.startswith('model '):
                    continue
                if stripped.startswith('modalities') or stripped.startswith('available') or stripped.startswith('Loading'):
                    continue
                # 遇到 prompt 回显 — 移除紧邻的原文行，然后停止
                if stripped.startswith('> '):
                    if result_lines:
                        result_lines.pop(0)  # 译文之后的第一行是原文，不是译文
                    break
                if stripped.startswith('/'):
                    continue
                if stripped and not any(c.isalnum() for c in stripped):
                    continue
                if stripped:
                    result_lines.insert(0, stripped)
            translation = '\n'.join(result_lines)

            # 清理停止标记
            for stop in STOP_TOKENS:
                translation = translation.replace(stop, "")

            return translation.strip()

        except subprocess.TimeoutExpired:
            return "翻译超时"
        except Exception as e:
            return f"翻译错误: {e}"

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

    service.interactive_mode()


if __name__ == "__main__":
    main()
