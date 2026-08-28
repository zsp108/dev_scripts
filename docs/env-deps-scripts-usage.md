# 环境与依赖安装脚本使用说明 / Environment & Dependencies Scripts Usage

本文档提供了 `scripts/` 目录下用于环境初始化和各类开发依赖自动安装脚本的使用说明。
This document provides usage instructions for the environment initialization and dependency installation scripts in the `scripts/` directory.

---

### `env_init.sh`
- **中**：环境初始化脚本。用于配置工作目录、系统字符集以及网络代理。
- **EN**：Environment initialization script. Used for configuring workspace, system charset, and network proxies.
- **Usage (用法)**:
  ```bash
  ./scripts/env_init.sh [mode]
  # mode: env (仅环境), proxy (仅代理), all (默认, 环境+代理)
  # mode: env (env only), proxy (proxy only), all (default, env+proxy)
  ```

### `docker_install.sh`
- **中**：自动安装与卸载 Docker 及相关组件。
- **EN**：Automatically install and uninstall Docker and related components.
- **Usage (用法)**:
  ```bash
  sudo ./scripts/docker_install.sh [version] [channel] [data-root] # 安装 / Install
  sudo ./scripts/docker_install.sh uninstall [--purge-data]        # 卸载 / Uninstall
  ```

### `go_install.sh`
- **中**：自动下载并安装/卸载 Golang 环境。
- **EN**：Automatically download and install/uninstall Golang environment.
- **Usage (用法)**:
  ```bash
  sudo ./scripts/go_install.sh [version]             # 安装指定版本 / Install specific version
  ./scripts/go_install.sh list                       # 列出可用版本 / List available versions
  sudo ./scripts/go_install.sh uninstall [version|all] # 卸载 / Uninstall
  ```

### `git_install.sh`
- **中**：自动下载并编译安装 Git。
- **EN**：Automatically download and compile Git from source.
- **Usage (用法)**:
  ```bash
  sudo ./scripts/git_install.sh [version]  # 安装指定版本 / Install specific version
  ./scripts/git_install.sh list            # 列出可用版本 / List available versions
  sudo ./scripts/git_install.sh uninstall  # 卸载 / Uninstall
  ```

### `nodejs_install.sh`
- **中**：自动安装与卸载 Node.js LTS 及 npm。
- **EN**：Automatically install and uninstall Node.js LTS and npm.
- **Usage (用法)**:
  ```bash
  sudo ./scripts/nodejs_install.sh [version]  # 安装 / Install (e.g., 20, 22, lts)
  ./scripts/nodejs_install.sh list            # 列表 / List versions
  sudo ./scripts/nodejs_install.sh uninstall  # 卸载 / Uninstall
  ```

### `protobuf_install.sh`
- **中**：自动下载并安装 Protobuf (protoc) 及 protoc-gen-go 插件。
- **EN**：Automatically download and install Protobuf (protoc) and protoc-gen-go plugin.
- **Usage (用法)**:
  ```bash
  ./scripts/protobuf_install.sh [protoc_version] [protoc_gen_go_version] # 安装 / Install
  ./scripts/protobuf_install.sh list                                     # 列表 / List versions
  ./scripts/protobuf_install.sh uninstall                                # 卸载 / Uninstall
  ```

### `vim_go_install.sh`
- **中**：自动安装与配置 vim-go 插件及 Go 开发工具环境。
- **EN**：Automatically install and configure the vim-go plugin and Go development tools.
- **Usage (用法)**:
  ```bash
  ./scripts/vim_go_install.sh [branch_or_tag]  # 安装 / Install (default: master)
  ./scripts/vim_go_install.sh uninstall        # 卸载 / Uninstall
  ```

### `gitlint_install.sh`
- **中**：自动下载并安装 gitlint commit message 校验工具。
- **EN**：Automatically download and install gitlint tool for commit message validation.
- **Usage (用法)**:
  ```bash
  ./scripts/gitlint_install.sh            # 安装 / Install
  ./scripts/gitlint_install.sh uninstall  # 卸载 / Uninstall
  ```
