#!/usr/bin/env python3
"""
翻译测试脚本
"""

import sys
import os

# 添加当前目录到路径
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from translate import TranslationService, LANGUAGES

def test_translation():
    """测试翻译功能"""
    
    print("=== 翻译测试 ===\n")
    
    # 创建翻译服务
    service = TranslationService()
    
    # 加载模型
    print("加载模型...")
    if not service.load_model():
        print("错误: 模型加载失败")
        print("请先运行: ./install.sh --download-model")
        return False
    
    print("模型加载成功\n")
    
    # 测试用例
    test_cases = [
        {
            "name": "英译中",
            "text": "Hello, how are you today?",
            "expected_contains": ["你好", "吗"]
        },
        {
            "name": "中译英",
            "text": "今天天气真好，我们出去散步吧。",
            "expected_contains": ["weather", "walk", "today"]
        },
        {
            "name": "长句翻译",
            "text": "Artificial intelligence is transforming the way we live and work, bringing both opportunities and challenges to society.",
            "expected_contains": ["人工智能", "机遇", "挑战"]
        },
        {
            "name": "技术术语",
            "text": "The quantum computer uses qubits for computation.",
            "expected_contains": ["量子", "计算"]
        }
    ]
    
    # 运行测试
    passed = 0
    failed = 0
    
    for test in test_cases:
        print(f"测试: {test['name']}")
        print(f"原文: {test['text']}")
        
        translation = service.translate(test['text'])
        print(f"译文: {translation}")
        
        # 检查翻译结果
        if any(keyword in translation for keyword in test['expected_contains']):
            print("✓ 通过")
            passed += 1
        else:
            print("✗ 失败")
            print(f"  期望包含: {test['expected_contains']}")
            failed += 1
        
        print()
    
    # 显示结果
    print("=== 测试结果 ===")
    print(f"通过: {passed}")
    print(f"失败: {failed}")
    print(f"总计: {passed + failed}")
    
    return failed == 0

def test_languages():
    """测试语言支持"""
    
    print("\n=== 语言支持测试 ===\n")
    
    service = TranslationService()
    
    if not service.load_model():
        print("错误: 模型加载失败")
        return False
    
    # 测试多种语言
    test_text = "Good morning"
    
    for code, name in sorted(LANGUAGES.items()):
        try:
            translation = service.translate(test_text, target_lang=name)
            print(f"{code:8} ({name:20}): {translation}")
        except Exception as e:
            print(f"{code:8} ({name:20}): 错误 - {e}")
    
    return True

def main():
    """主函数"""
    
    print("Qubes Translation Qube - 测试\n")
    
    # 运行翻译测试
    if not test_translation():
        print("\n翻译测试失败")
        sys.exit(1)
    
    # 运行语言测试
    if '--all-languages' in sys.argv:
        test_languages()
    
    print("\n所有测试完成！")

if __name__ == "__main__":
    main()
