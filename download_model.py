#!/usr/bin/env python3
"""
下载 HY-MT1.5 翻译模型
"""

import os
import sys
import requests
from pathlib import Path
from tqdm import tqdm

# 模型配置
MODELS = {
    "1.25bit": {
        "url": "https://huggingface.co/AngelSlim/Hy-MT1.5-1.8B-1.25bit-GGUF/resolve/main/Hy-MT1.5-1.8B-1.25bit-Q4_K_M.gguf",
        "filename": "Hy-MT1.5-1.8B-1.25bit-Q4_K_M.gguf",
        "size": "约 440MB",
        "description": "1.25bit 极度量化版本，内存占用最小"
    },
    "2bit": {
        "url": "https://huggingface.co/AngelSlim/Hy-MT1.5-1.8B-2bit-GGUF/resolve/main/Hy-MT1.5-1.8B-2bit-Q4_K_M.gguf",
        "filename": "Hy-MT1.5-1.8B-2bit-Q4_K_M.gguf",
        "size": "约 574MB",
        "description": "2bit 量化版本，质量更好"
    }
}

def download_model(model_key="1.25bit", output_dir="models"):
    """下载模型"""
    
    if model_key not in MODELS:
        print(f"错误: 未知模型 '{model_key}'")
        print(f"可用模型: {', '.join(MODELS.keys())}")
        return False
    
    model_info = MODELS[model_key]
    
    # 创建输出目录
    os.makedirs(output_dir, exist_ok=True)
    
    output_path = os.path.join(output_dir, model_info["filename"])
    
    # 检查是否已存在
    if os.path.exists(output_path):
        print(f"模型已存在: {output_path}")
        return True
    
    print(f"下载模型: {model_info['description']}")
    print(f"大小: {model_info['size']}")
    print(f"URL: {model_info['url']}")
    print(f"保存到: {output_path}")
    print()
    
    try:
        # 使用 requests 下载，显示进度
        response = requests.get(model_info["url"], stream=True)
        response.raise_for_status()
        
        total_size = int(response.headers.get('content-length', 0))
        
        with open(output_path, 'wb') as f, tqdm(
            desc=model_info["filename"],
            total=total_size,
            unit='B',
            unit_scale=True,
            unit_divisor=1024,
        ) as bar:
            for chunk in response.iter_content(chunk_size=8192):
                size = f.write(chunk)
                bar.update(size)
        
        print(f"\n下载完成: {output_path}")
        return True
    except Exception as e:
        print(f"\n下载失败: {e}")
        return False

def main():
    import argparse
    
    parser = argparse.ArgumentParser(description='下载 HY-MT1.5 翻译模型')
    parser.add_argument('--model', '-m', default='1.25bit',
                       choices=list(MODELS.keys()),
                       help='模型版本 (默认: 1.25bit)')
    parser.add_argument('--output', '-o', default='models',
                       help='输出目录 (默认: models)')
    parser.add_argument('--list', '-l', action='store_true',
                       help='列出可用模型')
    
    args = parser.parse_args()
    
    if args.list:
        print("可用模型:")
        for key, info in MODELS.items():
            print(f"  {key}: {info['description']} ({info['size']})")
        return
    
    success = download_model(args.model, args.output)
    sys.exit(0 if success else 1)

if __name__ == "__main__":
    main()
