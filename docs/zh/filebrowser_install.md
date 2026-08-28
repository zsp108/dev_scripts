# filebrowser_install.sh 使用说明

## 脚本简介
FileBrowser 是一款轻巧且功能强大的 Web 文件管理器。此脚本提供了其自动化安装服务，并深度定制了**多用户存储隔离**模型（完美协同 Samba 部署）。同时，脚本具备智能三级自适应探测能力，自动将 FileBrowser 注册为系统后台服务（如 Systemd）。

## 使用示例

### 1. 交互式安装与配置 (推荐)
直接运行脚本，脚本将进入交互模式，一步步引导您设置管理员账号、监听端口等。
```bash
./scripts/filebrowser_install.sh
```

### 2. 快速全自动安装
如果您希望在自动化流水线或非交互环境中使用，可以传入所有必要参数：
```bash
# 格式: sudo ./filebrowser_install.sh install [管理目录路径] [监听端口] [管理员密码]
sudo ./scripts/filebrowser_install.sh install /data/filebrowser 8080 mySecretPassword
```

### 3. 服务运维与管理
安装完成后，您可以使用标准服务管理命令控制它（基于 Systemd）：
```bash
sudo systemctl status filebrowser
sudo systemctl restart filebrowser
sudo systemctl stop filebrowser
```

