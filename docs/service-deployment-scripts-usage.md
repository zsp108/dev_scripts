# 服务部署脚本使用说明 / Service Deployment Scripts Usage

本文档提供了 `scripts/` 目录下用于一键部署常用服务的脚本使用说明。
This document provides usage instructions for the service deployment scripts in the `scripts/` directory.

---

### `samba_install.sh`
- **中**：Samba 自动化部署脚本，支持多用户存储隔离、自定义端口以及全平台挂载优化。
- **EN**：Samba automated deployment script, supports multi-user storage isolation, custom ports, and cross-platform mounting optimizations.
- **Usage (用法)**:
  ```bash
  sudo ./scripts/samba_install.sh
  ```

### `filebrowser_install.sh`
- **中**：FileBrowser 轻量级 Web 文件管理器自动化安装脚本，支持多用户存储隔离，可完美协同 Samba。
- **EN**：Automated installation script for FileBrowser (a lightweight Web file manager), supports multi-user storage isolation and works perfectly with Samba.
- **Usage (用法)**:
  ```bash
  ./scripts/filebrowser_install.sh                                                  # 交互式运行 / Interactive
  sudo ./scripts/filebrowser_install.sh install [admin_dir] [port] [admin_password] # 快速安装 / Quick install
  ```

### `nginx_download_install.sh`
- **中**：安装并配置 Nginx 下载站点，自动生成下载目录的 index.html。
- **EN**：Install and configure Nginx download site, auto-generating index.html for download directories.
- **Usage (用法)**:
  ```bash
  sudo ./scripts/nginx_download_install.sh [download-root] [listen-port]
  ```

### `derper_install.sh`
- **中**：Tailscale DERP 一键安装与 SysV Service 注册脚本 (完全可配置版)。
- **EN**：Tailscale DERP Server one-click installation and SysV Service registration script (fully configurable).
- **Usage (用法)**:
  ```bash
  sudo ./scripts/derper_install.sh [DOMAIN] [PORT] [APP_DIR] [LOG_FILE]
  ```
