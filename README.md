# Qubes Translation Qube

基于腾讯混元 HY-MT1.5 翻译模型的 Qubes OS 离线翻译 qube。**一行命令安装，Web UI 粘贴即翻译**。

## 功能

- **离线翻译**：无需网络，数据不出设备
- **33 种语言**：中英互译优化，支持 1056 个翻译方向
- **Web 界面**：极简暗色 UI，粘贴文本→选语言→翻
- **交互模式**：终端直接输入，即时翻译
- **低资源**：500MB 内存 + 1.5GB 存储即可运行

## 系统要求

- Qubes OS 4.2+
- 翻译 qube：**1GB 内存**（推荐），500MB 可勉强运行
- 存储空间：约 2GB（含模型 1.1GB）
- `xclip`（自动安装）

## 快速开始

### 1. 创建翻译 qube

在 dom0 终端执行：

```bash
qvm-create --class AppVM --template debian-13-minimal --label blue translation
qvm-prefs translation memory 1024
qvm-start translation
```

### 2. 在翻译 qube 中一键安装

```bash
curl -sSL https://raw.githubusercontent.com/iasds/qubes-translation-qube/main/install.sh -o install.sh
chmod +x install.sh
./install.sh --download-model
```

安装过程约 5-10 分钟（含编译 llama.cpp + 下载 1.1GB 模型）。

### 3. 使用

```bash
# 交互模式
./translate.sh

# 剪贴板监控（在翻译 qube 终端中打开，然后去其他 VM 复制文本）
./translate.sh --clipboard

# 单次翻译
./translate.sh --text "Hello world"

# Web 界面（在浏览器访问 http://翻译qube的IP:8080）
./webui.sh
```

## 使用演示

**交互模式：**
```
=== Qubes Translation Qube ===
输入文本进行翻译，/help 查看帮助，/quit 退出

> Hello, how are you?
你好，你怎么样？

> 今天天气真好
The weather is really nice today.
```

**Web 界面：**
打开浏览器访问翻译 qube 的 IP:8080，粘贴文本、选语言、点翻译。

**语言切换：**
```
> /lang zh ja          # 中译日
语言: Chinese -> Japanese
> /lang en zh          # 英译中
语言: English -> Chinese
> /languages           # 查看所有支持的语言
```

## 性能

| 场景 | 耗时 |
|------|------|
| 首次启动（从磁盘加载模型） | ~45s |
| 后续翻译（从缓存加载） | ~4s |
| 推理速度 | ~15 t/s (Q4_K_M) |

## 安装说明

安装脚本自动完成：
1. 检查系统内存和磁盘空间
2. `sudo apt install` 依赖（python3, cmake, git, xclip）
3. 编译 llama.cpp（仅编译 llama-cli）
4. 创建翻译脚本、配置、启动器
5. 下载 Q4_K_M 量化模型（约 1.1GB）

## 配置

编辑 `config.json`：

```json
{
  "model_path": "models/Hy-MT1.5-1.8B-Q4_K_M.gguf",
  "default_source_lang": "auto",
  "default_target_lang": "English",
  "clipboard_poll_interval": 0.5,
  "max_tokens": 256,
  "temperature": 0.7
}
```

可选模型：`Q4_K_M`（1.1GB，推荐）、`Q6_K`（764MB，更快更小）。

## 提示词模板

本项目使用官方推荐的提示词：

**中译外**：`将以下文本翻译为{目标语言}，注意只需要输出翻译后的结果，不要额外解释：`

**外译中**：`将以下文本翻译为中文，注意只需要输出翻译后的结果，不要额外解释：`

## 故障排除

**模型加载失败**：`ls models/` 检查模型文件，运行 `./install.sh --download-model` 重新下载。

**依赖缺失**：`sudo apt install python3`。

## 致谢

- [腾讯混元 HY-MT](https://github.com/Tencent-Hunyuan/HY-MT) - 翻译模型
- [llama.cpp](https://github.com/ggml-org/llama.cpp) - 推理引擎
- [Qubes OS](https://www.qubes-os.org/) - 安全操作系统

## 许可证

MIT。模型使用请遵循 [HY-MT 许可](https://huggingface.co/tencent/HY-MT1.5-1.8B)。
