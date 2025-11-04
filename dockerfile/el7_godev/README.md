# CentOS 7 Go Development Environment

基于 CentOS 7 的 Go 和 Git 开发环境 Docker 镜像，支持自定义 Go 和 Git 版本。

## 功能特性

- 🐧 基于 CentOS 7
- 🐹 支持自定义 Go 版本
- 📦 支持自定义 Git 版本
- 🔄 版本同步（Makefile 与 Dockerfile 联动）
- 🛠️ 完整的开发工具链
- 📝 自动化构建流程

## 默认版本

- **Go 版本**: 1.25.3
- **Git 版本**: 2.51.0

## 快速开始

### 1. 构建镜像

```bash
# 使用默认版本构建
make build

# 指定版本构建
make build GO_VERSION=1.24.0 GIT_VERSION=2.50.0
```

### 2. 运行容器

```bash
# 后台运行容器
make run

# 后台运行指定标签的容器
make run-tag TAG=v1.0.0

# 交互式运行（直接进入 shell）
make shell

# 进入运行中的容器
make exec
```

### 3. 验证安装

进入容器后验证工具版本：

```bash
# 方法1：交互式运行并验证
make shell
# 在容器内执行
go version    # 验证 Go 版本
git --version # 验证 Git 版本
exit

# 方法2：后台运行后进入容器
make run
make exec
# 在容器内执行
go version
git --version
exit
```

## Makefile 使用指南

### 构建命令

| 命令 | 说明 | 示例 |
|------|------|------|
| `make build` | 构建默认版本镜像 | `make build` |
| `make build-tag` | 构建自定义标签镜像 | `make build-tag TAG=v1.0.0` |
| `make prepare` | 准备构建环境（下载依赖） | `make prepare` |

### 运行命令

| 命令 | 说明 | 示例 |
|------|------|------|
| `make run` | 后台运行最新版本镜像 | `make run` |
| `make run-tag` | 后台运行指定标签镜像 | `make run-tag TAG=v1.0.0` |
| `make shell` | 交互式运行容器（直接进入shell） | `make shell` |
| `make exec` | 进入运行中的容器 | `make exec` |

### 管理命令

| 命令 | 说明 | 示例 |
|------|------|------|
| `make images` | 查看本地镜像列表 | `make images` |
| `make push` | 推送镜像到仓库 | `make push` |
| `make clean` | 清理本地镜像和容器 | `make clean` |
| `make help` | 显示帮助信息 | `make help` |

## 自定义配置

### 版本配置

通过环境变量自定义 Go 和 Git 版本：

```bash
# 自定义 Go 版本
make build GO_VERSION=1.25.3

# 自定义 Git 版本
make build GIT_VERSION=2.42.0

# 同时自定义两个版本
make build GO_VERSION=1.25.3 GIT_VERSION=2.42.0
```

### 镜像命名

自定义镜像名称：

```bash
# 自定义镜像名称
IMAGE_NAME=my-godev make build
```

### 自定义标签

```bash
# 使用自定义标签构建
make build-tag TAG=production-v1.2.3

# 运行自定义标签镜像
make run-tag TAG=production-v1.2.3
```

## 构建流程

1. **准备阶段** (`make prepare`)
   - 复制安装脚本到本地目录
   - 检查并下载 Go 和 Git 源码包
   - 创建构建环境

2. **构建阶段** (`make build`)
   - 读取 Makefile 中的版本配置
   - 传递版本参数到 Dockerfile
   - 构建 Docker 镜像
   - 自动打标签：`<镜像名>:<Go版本>-git<Git版本>` 和 `<镜像名>:latest`

## 常用工作流程

### 开发测试流程
```bash
# 1. 构建镜像
make build

# 2. 直接进入容器进行开发
make shell

# 3. 或者后台运行容器，随时进入
make run
make exec

# 4. 测试完成后清理
make clean
```

### 版本测试流程
```bash
# 1. 测试特定版本组合
make build GO_VERSION=1.24.0 GIT_VERSION=2.50.0

# 2. 运行容器验证版本
make shell
# 在容器内：go version, git --version

# 3. 如有问题，快速切换版本
make build GO_VERSION=1.23.0 GIT_VERSION=2.49.0
make shell
```

## 版本同步机制

本项目的版本同步机制确保 Makefile 和 Dockerfile 中的版本保持一致：

- ✅ Makefile 定义默认版本变量
- ✅ Dockerfile 接收构建参数
- ✅ 脚本动态使用指定版本
- ✅ 支持命令行覆盖

## 目录结构

```
.
├── Makefile              # 构建配置文件
├── Dockerfile            # Docker 镜像定义
├── README.md             # 项目说明文档
├── packages/             # 下载的软件包目录
└── scripts/              # 安装脚本目录，由项目根目录下sctips拷贝所需脚本存放
```

## 环境变量

| 变量名 | 默认值 | 说明 |
|--------|--------|------|
| `GO_VERSION` | 1.25.3 | Go 编程语言版本 |
| `GIT_VERSION` | 2.51.0 | Git 版本控制系统版本 |
| `IMAGE_NAME` | centos7-godev | Docker 镜像名称 |
| `TAG` | - | 自定义镜像标签 |

## 支持的版本

### Go 版本支持
- 1.20.x 系列
- 1.21.x 系列
- 1.22.x 系列
- 1.23.x 系列
- 1.24.x 系列
- 1.25.x 系列

### Git 版本支持
- 2.40.x 系列
- 2.41.x 系列
- 2.42.x 系列
- 2.43.x 系列
- 2.44.x 系列
- 2.45.x 系列
- 2.50.x 系列
- 2.51.x 系列

## 常见问题

### Q: 如何更改默认版本？
A: 修改 Makefile 开头的 `GO_VERSION` 和 `GIT_VERSION` 变量。

### Q: `make run` 和 `make shell` 有什么区别？
A: `make run` 以后台模式运行容器，需要用 `make exec` 进入；`make shell` 直接以交互式模式运行容器并进入 shell。

### Q: `make exec` 提示容器未运行怎么办？
A: 确保先用 `make run` 或 `make run-tag` 启动容器，然后再使用 `make exec` 进入。

### Q: 构建失败怎么办？
A: 检查网络连接，确保能访问 Go 和 Git 的下载源。

### Q: 如何验证版本是否正确？
A: 运行容器后执行 `go version` 和 `git --version` 命令。

### Q: 可以同时使用不同版本吗？
A: 可以，通过命令行参数指定：`make build GO_VERSION=1.24.0 GIT_VERSION=2.50.0`

### Q: 如何快速测试多个版本组合？
A: 使用常用工作流程中的版本测试方法，连续构建并运行容器进行验证。

## 许可证

Author: zsp108

本项目基于 MIT 许可证开源。