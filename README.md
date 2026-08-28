# dev_scripts

**dev_scripts** 是一个用于自动化环境配置、依赖安装和常见服务部署的脚本集合。
**dev_scripts** is a collection of scripts for automated environment configuration, dependency installation, and common service deployments.

## 目录 / Table of Contents
- [功能特性 / Features](#功能特性--features)
- [目录结构 / Directory Structure](#目录结构--directory-structure)
- [基于 Makefile 的快捷命令 / Makefile Quick Commands](#基于-makefile-的快捷命令--makefile-quick-commands)
- [脚本独立使用说明 / Scripts Usage Documentation](#脚本独立使用说明--scripts-usage-documentation)

## 功能特性 / Features

- **环境与依赖管理 / Environment & Dependencies**: 一键安装 Golang, Node.js, Git, Docker, Protobuf, Vim-go 等。
- **服务部署 / Service Deployment**: 快速部署 Samba, FileBrowser, Nginx 下载站, Tailscale DERP 节点等，支持多用户隔离和自定义配置。
- **实用工具 / Utility Tools**: 局域网 IP 扫描、V2Ray 配置生成、账号快速切换等。
- **Git 规范检查 / Git Linting**: 内置 Git commit message 检查工具及 Hooks，规范团队提交流程。

## 目录结构 / Directory Structure

```text
├── Makefile                # 快捷指令入口 / Quick command entry
├── docs/                   # 项目文档目录 / Project documentation directory
│   ├── zh/                 # 中文独立脚本使用说明 / Chinese Scripts Documentation
│   └── en/                 # 英文独立脚本使用说明 / English Scripts Documentation
├── scripts/                # 核心安装脚本 / Core installation scripts
│   ├── tools/              # 实用工具脚本 / Utility tools
│   └── templates/          # 配置文件模板 / Configuration templates
└── README.md               # 项目总说明 / Project README
```

## 基于 Makefile 的快捷命令 / Makefile Quick Commands

为了简化直接调用脚本的复杂度，本项目深度集成了 `Makefile`。您可以通过执行 `make` 及其相应的目标任务（target）来快速运行对应的脚本。
To simplify script invocation, this project deeply integrates a `Makefile`. You can easily run the corresponding scripts by executing `make` targets.

### 通用命令 (General Commands)
```bash
make help           # 查看所有可用的 make 命令及说明 / Show all available make targets
make check          # 检查所有开发工具和服务的状态 / Check status of all dev tools and services
make list-scripts   # 列出所有可用的脚本 / List all available scripts
make test           # 验证 scripts/ 目录下所有脚本的语法规范 / Validate syntax of all shell scripts
make docs           # 显示项目文档引导内容 / Show project documentation guide
```

### 开发工具链安装 (Development Tools Installation)
大部分开发依赖都提供了对应的 `install-[name]` 和 `uninstall-[name]` 命令。
Most development dependencies provide corresponding `install-[name]` and `uninstall-[name]` commands.

**Go / Node.js / Git / Protobuf / Vim-go:**
```bash
make list-go-versions                  # 列出官方支持的 Go 版本
make install-go                        # 安装 Go 环境（默认版本）
make install-go GO_VERSION=1.25.3      # 传递变量以安装特定版本的 Go
make uninstall-go                      # 卸载 Go 环境

make install-nodejs                    # 自动安装 Node.js LTS
make install-git                       # 编译安装最新稳定的 Git
make install-git GIT_VERSION=2.43.0    # 编译安装特定版本的 Git
make install-protobuf                  # 安装 Protobuf 编译器及 Go 插件
make install-vim-go                    # 为 Vim 安装 Go IDE 开发辅助插件
```

### 环境与代码质量管理 (Environment & Code Quality)
```bash
make init-env                          # 初始化终端字符集及 Workspace 环境
make setup                             # 一键安装所有基础开发工具 (Go/Node/Git/Docker/Gitlint)

make install-gitlint                   # 安装 gitlint 工具
make install-hooks                     # 在当前仓库部署预检 hooks (pre-commit, commit-msg)
make gitlint-all                       # 自动校验仓库中所有的 Commit 记录格式
```

### 服务部署与管理 (Service Deployment)
```bash
make install-docker                    # 安装 Docker 及 Docker Compose
make install-samba                     # 部署 Samba 多用户隔离服务
make install-filebrowser               # 部署 FileBrowser 轻量级网盘服务
make install-nginx-download            # 部署 Nginx 静态下载页面
make install-derper                    # 部署 Tailscale DERP 中继节点
```

## 脚本独立使用说明 / Scripts Usage Documentation

如果您不想使用 Makefile，或需要传入更复杂的定制参数，可以直接运行对应的脚本。
我们为每个脚本提供了独立的中、英文说明文档。请通过下表中的链接快速访问：
If you prefer not to use the Makefile, or need to pass complex custom parameters, you can run the scripts directly. We provide independent Chinese and English documentation for each script below:

### 环境与依赖安装 / Environment & Dependencies
| Script 脚本 | 中文文档 (Chinese) | 英文文档 (English) |
| ----------- | ---------------- | ---------------- |
| `env_init.sh` | [env_init_zh](docs/zh/env_init.md) | [env_init_en](docs/en/env_init.md) |
| `docker_install.sh` | [docker_install_zh](docs/zh/docker_install.md) | [docker_install_en](docs/en/docker_install.md) |
| `go_install.sh` | [go_install_zh](docs/zh/go_install.md) | [go_install_en](docs/en/go_install.md) |
| `git_install.sh` | [git_install_zh](docs/zh/git_install.md) | [git_install_en](docs/en/git_install.md) |
| `nodejs_install.sh` | [nodejs_install_zh](docs/zh/nodejs_install.md) | [nodejs_install_en](docs/en/nodejs_install.md) |
| `protobuf_install.sh` | [protobuf_install_zh](docs/zh/protobuf_install.md) | [protobuf_install_en](docs/en/protobuf_install.md) |
| `vim_go_install.sh` | [vim_go_install_zh](docs/zh/vim_go_install.md) | [vim_go_install_en](docs/en/vim_go_install.md) |
| `gitlint_install.sh` | [gitlint_install_zh](docs/zh/gitlint_install.md) | [gitlint_install_en](docs/en/gitlint_install.md) |

### 服务部署 / Service Deployment
| Script 脚本 | 中文文档 (Chinese) | 英文文档 (English) |
| ----------- | ---------------- | ---------------- |
| `samba_install.sh` | [samba_install_zh](docs/zh/samba_install.md) | [samba_install_en](docs/en/samba_install.md) |
| `filebrowser_install.sh`| [filebrowser_install_zh](docs/zh/filebrowser_install.md) | [filebrowser_install_en](docs/en/filebrowser_install.md) |
| `nginx_download_install.sh` | [nginx_download_install_zh](docs/zh/nginx_download_install.md) | [nginx_download_install_en](docs/en/nginx_download_install.md) |
| `derper_install.sh` | [derper_install_zh](docs/zh/derper_install.md) | [derper_install_en](docs/en/derper_install.md) |

### 实用工具 / Utility Tools
*(Makefile 暂未包含工具类脚本的直接入口，请通过命令行调用)*
*(Utility scripts do not have Makefile targets, please call them via command line)*
| Script 脚本 | 中文文档 (Chinese) | 英文文档 (English) |
| ----------- | ---------------- | ---------------- |
| `scan_ip / scan_ip2` | [scan_ip_zh](docs/zh/scan_ip.md) | [scan_ip_en](docs/en/scan_ip.md) |
| `v2ray_conf_setting.sh` | [v2ray_conf_setting_zh](docs/zh/v2ray_conf_setting.md) | [v2ray_conf_setting_en](docs/en/v2ray_conf_setting.md) |
| `codex_switch.sh` | [codex_switch_zh](docs/zh/codex_switch.md) | [codex_switch_en](docs/en/codex_switch.md) |

### 其他指南 / Other Guides
- [Git 提交规范指南 / Git Commit Guide](docs/git-commit-guide.md)
