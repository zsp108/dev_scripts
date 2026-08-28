# dev_scripts

**dev_scripts** 是一个用于自动化环境配置、依赖安装和常见服务部署的脚本集合。
**dev_scripts** is a collection of scripts for automated environment configuration, dependency installation, and common service deployments.

## 目录 / Table of Contents
- [功能特性 / Features](#功能特性--features)
- [目录结构 / Directory Structure](#目录结构--directory-structure)
- [快速开始 / Quick Start](#快速开始--quick-start)
- [文档指引 / Documentation Guide](#文档指引--documentation-guide)

## 功能特性 / Features

- **环境与依赖管理 / Environment & Dependencies**: 一键安装 Golang, Node.js, Git, Docker, Protobuf, Vim-go 等。
- **服务部署 / Service Deployment**: 快速部署 Samba, FileBrowser, Nginx 下载站, Tailscale DERP 节点等，支持多用户隔离和自定义配置。
- **实用工具 / Utility Tools**: 局域网 IP 扫描、V2Ray 配置生成、账号快速切换等。
- **Git 规范检查 / Git Linting**: 内置 Git commit message 检查工具及 Hooks，规范团队提交流程。

## 目录结构 / Directory Structure

```text
├── Makefile                # 快捷指令入口 / Quick command entry
├── docs/                   # 项目文档目录 / Project documentation directory
├── scripts/                # 核心安装脚本 / Core installation scripts
│   ├── tools/              # 实用工具脚本 / Utility tools
│   └── templates/          # 配置文件模板 / Configuration templates
└── README.md               # 项目总说明 / Project README
```

## 快速开始 / Quick Start

您可以使用 `make` 命令快速查看和运行相关功能：
You can use the `make` command to quickly view and run related features:

```bash
make check          # 检查所有开发工具和服务的状态 / Check status of all dev tools and services
make list-scripts   # 列出所有可用的脚本 / List all available scripts
make docs           # 显示项目文档内容 / Show project documentation
```

## 文档指引 / Documentation Guide

请参考 `docs/` 目录下的详细使用说明：
Please refer to the detailed usage guides in the `docs/` directory:

- [环境与依赖安装脚本说明 / Environment & Dependencies Scripts Usage](docs/env-deps-scripts-usage.md)
- [服务部署脚本说明 / Service Deployment Scripts Usage](docs/service-deployment-scripts-usage.md)
- [实用工具脚本说明 / Utility Tools Usage](docs/utility-tools-usage.md)
- [Git 提交规范指南 / Git Commit Guide](docs/git-commit-guide.md)
