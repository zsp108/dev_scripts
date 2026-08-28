# docker_install.sh 使用说明

## 脚本简介
本脚本旨在为您提供一种快速、可靠的自动化方式来安装与卸载 Docker 及相关组件（如 Docker Compose）。它支持自定义安装的 Docker 版本、发布渠道以及 Docker 的数据存储路径，以满足不同的定制化需求。

## 参数说明
- `[version]`：(可选) 您希望安装的 Docker 版本号（例如 `24.0.5`）。如果不提供，默认安装最新版本。
- `[channel]`：(可选) 软件发布渠道（如 `stable`, `test`, `nightly`）。默认为 `stable`。
- `[data-root]`：(可选) Docker 容器及镜像的本地数据根目录。默认为 `/var/lib/docker`。

## 使用示例

### 1. 默认安装 (推荐)
直接执行，将以默认设置安装最新稳定版的 Docker：
```bash
sudo ./scripts/docker_install.sh
```

### 2. 指定版本与数据目录安装
如果您需要安装特定版本，并把镜像数据存储在更大的硬盘分区上（如 `/data/docker`）：
```bash
sudo ./scripts/docker_install.sh 24.0.5 stable /data/docker
```

### 3. 标准卸载
卸载 Docker 引擎及相关组件，但**保留**所有的镜像、容器和配置文件：
```bash
sudo ./scripts/docker_install.sh uninstall
```

### 4. 彻底卸载并清理数据
卸载 Docker 的同时彻底清除所有相关数据和容器（**警告：此操作不可逆，请提前备份！**）：
```bash
sudo ./scripts/docker_install.sh uninstall --purge-data
```

