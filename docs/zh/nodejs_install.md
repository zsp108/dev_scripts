# nodejs_install.sh 使用说明

## 脚本简介
这是一个全平台自动化的 Node.js 及开发者 AI 命令行工具一键安装与生命周期管理脚本：
1. **多发行版全支持**：深度适配 Ubuntu / Debian、CentOS / RHEL / Rocky Linux / AlmaLinux 以及 macOS (Homebrew)。
2. **多版本随心选**：支持通过参数安装指定大版本（如 `20`、`22`）或默认最新 LTS 长期支持版。
3. **可选开发者 AI CLI（交互式按需选择）**：Node.js 安装完成后，脚本会友好提示用户**自主选择**是否安装 `@openai/codex` 与 `@google/gemini-cli` 工具，亦支持命令行参数直接指定。
4. **版本查询与干净卸载**：支持查询官方当前与历史 LTS 版本矩阵，并提供一键干净反向卸载。

---

## 常用命令示例

### 1. 交互式安装 LTS 长期支持版（推荐）
安装完成后会交互式提示您是否安装 AI 工具：
```bash
sudo ./scripts/nodejs_install.sh
# 或显式指定 lts:
sudo ./scripts/nodejs_install.sh lts
```

### 2. 命令行静默参数直接安装 AI 工具
```bash
# 同时安装 Node.js 22 和所有 AI 工具:
sudo ./scripts/nodejs_install.sh 22 --with-ai

# 仅安装 Node.js 20 + Codex CLI:
sudo ./scripts/nodejs_install.sh 20 --codex

# 仅安装 Node.js 22 + Gemini CLI:
sudo ./scripts/nodejs_install.sh 22 --gemini
```

### 3. 查看官方所有可用 LTS 与当前版本
```bash
./scripts/nodejs_install.sh list
```

### 4. 卸载 Node.js、npm 及相关工具
```bash
sudo ./scripts/nodejs_install.sh uninstall
```
