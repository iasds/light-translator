# Qubes Translation Qube

基于腾讯混元 HY-MT1.5 翻译模型的 Qubes OS 专用翻译 qube。

## 功能特点

- **本地翻译**：无需网络，数据不出设备
- **高质量翻译**：基于腾讯混元 HY-MT1.5 专业翻译模型
- **多语言支持**：33 种语言，1056 个翻译方向
- **中英互译优化**：专门优化的中英翻译质量
- **剪贴板集成**：自动检测剪贴板变化并翻译
- **终端交互**：简洁的终端界面，输入即翻译

## 系统要求

- Qubes OS 4.2+
- 翻译 qube 内存：**2GB**（模型运行需要）
- 存储空间：约 2GB（模型文件 + 依赖）
- CPU：x86_64（推荐多核）
- GPU：可选（Vulkan 加速）

## 快速开始

### 1. 创建翻译 qube

在 dom0 中执行：

```bash
# 基于 debian-13-minimal 创建 AppVM
qvm-create --class AppVM --template debian-13-minimal --label blue translation-qube

# 设置内存为 2GB
qvm-prefs translation-qube memory 2048

# 启动 qube
qvm-start translation-qube
```

### 2. 一键安装

在翻译 qube 中执行：

```bash
# 下载安装脚本
curl -sSL https://raw.githubusercontent.com/iasds/qubes-translation-qube/main/install.sh -o install.sh

# 执行安装
chmod +x install.sh
./install.sh
```

### 3. 使用翻译

安装完成后，在翻译 qube 中运行：

```bash
# 启动翻译服务
./translate.sh

# 或直接运行 Python 脚本
python3 translate.py
```

## 使用方法

### 基本使用

1. 在任意 qube 中选中文本
2. 使用 `Ctrl+Shift+C` 复制到全局剪贴板
3. 翻译 qube 自动检测并显示翻译结果

### 命令行交互

```bash
# 启动翻译服务
./translate.sh

# 输入文本后自动翻译
> Hello, how are you?
你好，你好吗？

> 今天天气真好
The weather is really nice today.

# 退出
> /quit
```

### 语言选择

默认支持中英互译，可通过命令切换：

```bash
# 切换到中译英
> /lang zh2en

# 切换到英译中
> /lang en2zh

# 查看支持的语言
> /languages
```

## 项目结构

```
qubes-translation-qube/
├── README.md          # 本文件
├── install.sh         # 一键安装脚本
├── translate.py       # 翻译服务主程序
├── translate.sh       # 启动脚本
├── requirements.txt   # Python 依赖
├── config.json        # 配置文件
└── models/            # 模型目录（安装后生成）
```

## 配置说明

编辑 `config.json` 可自定义配置：

```json
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
```

## 支持的语言

| 语言 | 中文名称 | 代码 |
|------|----------|------|
| Chinese | 中文 | zh |
| English | 英语 | en |
| French | 法语 | fr |
| Japanese | 日语 | ja |
| Korean | 韩语 | ko |
| German | 德语 | de |
| Spanish | 西班牙语 | es |
| Russian | 俄语 | ru |
| Arabic | 阿拉伯语 | ar |
| ... | ... | ... |

完整语言列表请运行 `/languages` 命令。

## 提示词模板

本项目使用官方推荐的提示词模板：

**中译外**：
```
将以下文本翻译为{目标语言}，注意只需要输出翻译后的结果，不要额外解释：

{源文本}
```

**外译中**：
```
将以下文本翻译为中文，注意只需要输出翻译后的结果，不要额外解释：

{源文本}
```

**非中文互译**：
```
Translate the following segment into {target_language}, without additional explanation.

{source_text}
```

## 故障排除

### 模型加载失败

```bash
# 检查模型文件是否存在
ls -lh models/

# 重新下载模型
./install.sh --download-model
```

### 内存不足

确保翻译 qube 内存设置为 2GB：

```bash
# 在 dom0 中检查
qvm-prefs translation-qube memory

# 设置为 2GB
qvm-prefs translation-qube memory 2048
```

### 剪贴板无法检测

```bash
# 安装 xclip
sudo apt install xclip

# 测试剪贴板
xclip -selection clipboard -o
```

## 性能优化

### CPU 优化

```bash
# 使用多线程（根据 CPU 核心数调整）
export OMP_NUM_THREADS=4
```

### GPU 加速（可选）

如果有支持 Vulkan 的 GPU：

```bash
# 安装 Vulkan 支持
sudo apt install vulkan-tools mesa-vulkan-drivers

# 使用 Vulkan 后端
python3 translate.py --gpu vulkan
```

## 开发说明

### 从源码构建

```bash
# 克隆仓库
git clone https://github.com/iasds/qubes-translation-qube.git
cd qubes-translation-qube

# 安装依赖
pip install -r requirements.txt

# 下载模型
python3 download_model.py

# 运行测试
python3 test_translation.py
```

### 贡献指南

欢迎提交 Issue 和 Pull Request！

1. Fork 本仓库
2. 创建特性分支 (`git checkout -b feature/xxx`)
3. 提交更改 (`git commit -m 'Add xxx'`)
4. 推送到分支 (`git push origin feature/xxx`)
5. 创建 Pull Request

## 许可证

本项目基于 MIT 许可证开源。

模型使用请遵循 [HY-MT 模型许可](https://huggingface.co/tencent/HY-MT1.5-1.8B)。

## 致谢

- [腾讯混元 HY-MT](https://github.com/Tencent-Hunyuan/HY-MT) - 翻译模型
- [llama.cpp](https://github.com/ggerganov/llama.cpp) - 推理引擎
- [Qubes OS](https://www.qubes-os.org/) - 安全操作系统

## 相关链接

- [HY-MT1.5 技术报告](https://arxiv.org/abs/2512.24092)
- [Sherry 量化论文](https://arxiv.org/abs/2601.07892)
- [Qubes OS qrexec 文档](https://www.qubes-os.org/doc/qrexec/)
