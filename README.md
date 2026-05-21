# 轻量翻译服务

基于腾讯混元 HY-MT1.5 翻译模型的离线翻译工具。**一行命令安装，Web UI 粘贴即翻译**。适用于任何 Linux 发行版，也可部署为 Qubes OS 翻译 qube。

## 功能

- **离线翻译**：无需网络，数据不出设备
- **33 种语言**：中英互译优化，覆盖 1056 个翻译方向
- **Web 界面**：极简暗色 UI，粘贴文本 → 选语言 → 翻译
- **命令行模式**：终端直接输入，即时翻译
- **低资源**：500MB 内存 + 1.5GB 存储即可运行

## 系统要求

- 任意 Linux 发行版（Debian/Ubuntu/Fedora/Arch 等）
- 内存：**1GB**（推荐），500MB 可勉强运行
- 存储：约 2GB（含模型 1.1GB）
- 依赖：git、cmake、gcc、make、python3（安装脚本自动处理）

## 快速开始

```bash
curl -sSL https://raw.githubusercontent.com/iasds/qubes-translation-qube/main/install.sh -o install.sh
chmod +x install.sh
./install.sh --download-model
```

安装约 5-10 分钟（编译 llama.cpp + 下载 1.1GB 模型）。

## 使用

```bash
# Web 界面（推荐）
./webui.sh
# 浏览器打开 http://localhost:8080

# 命令行交互模式
./translate.sh

# 单次翻译
./translate.sh --text "Hello world"
```

### Web 界面操作

1. 打开 `http://localhost:8080`
2. 粘贴文本
3. 选择目标语言
4. 点「翻译」或按 `Ctrl+Enter`

## 使用演示

**命令行模式：**
```
> Hello, how are you?
你好，你怎么样？

> 今天天气真好
The weather is really nice today.

> /lang zh ja
语言: Chinese -> Japanese
```

**Web 界面：**
`http://localhost:8080` — 暗色主题，33 种语言下拉选择，显示翻译耗时。

## 性能

| 场景 | 耗时 |
|------|------|
| 首次启动（从磁盘加载模型） | ~45s |
| 后续翻译（从缓存加载） | ~4s |
| 推理速度 | ~15 t/s (Q4_K_M) |

## 安装说明

安装脚本自动完成：
1. 检查系统内存和磁盘空间
2. 安装系统依赖（python3, cmake, git, build-essential）
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
  "max_tokens": 256,
  "temperature": 0.1,
  "n_threads": 2
}
```

可选模型：`Q4_K_M`（1.1GB，推荐）、`Q6_K`（764MB，更快更小）。

## Qubes OS 部署

如需在 Qubes OS 中部署为专用翻译 qube：

```bash
# dom0
qvm-create --class AppVM --template debian-13-minimal --label blue translation
qvm-prefs translation memory 1024
qvm-start translation

# 在 translation qube 中执行快速开始的安装命令
```

## 提示词模板

**中译外**：`将以下文本翻译为{目标语言}，注意只需要输出翻译后的结果，不要额外解释：`

**外译中**：`将以下文本翻译为中文，注意只需要输出翻译后的结果，不要额外解释：`

## 故障排除

**模型加载失败**：`ls models/` 检查模型文件，运行 `./install.sh --download-model` 重新下载。

**依赖缺失**：安装脚本会自动安装依赖。手动安装：`sudo apt install python3 cmake git build-essential`。

## 致谢

- [腾讯混元 HY-MT](https://github.com/Tencent-Hunyuan/HY-MT) - 翻译模型
- [llama.cpp](https://github.com/ggml-org/llama.cpp) - 推理引擎

## 许可证

MIT。模型使用请遵循 [HY-MT 许可](https://huggingface.co/tencent/HY-MT1.5-1.8B)。
