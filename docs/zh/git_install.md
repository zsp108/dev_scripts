# git_install.sh 使用说明

## 脚本简介
由于许多 Linux 发行版的包管理器（如 apt, yum）提供的 Git 版本过于陈旧，此脚本旨在帮您自动下载 Git 的最新官方源码，并完成本地化编译与安装，确保您能使用到 Git 的最新特性。

## 使用示例

### 1. 自动编译安装默认版本
安装脚本中设定的默认稳定版本（通常是 2.42.0 或更新版本）：
```bash
sudo ./scripts/git_install.sh
```

### 2. 编译安装指定版本
如果您需要与团队保持特定版本一致：
```bash
sudo ./scripts/git_install.sh 2.43.0
```

### 3. 列出可用的 Git 源码版本
通过网络拉取官方版本列表，帮助您决定安装哪个版本：
```bash
./scripts/git_install.sh list
```

### 4. 卸载编译版本的 Git
干净地卸载通过此脚本编译安装的 Git：
```bash
sudo ./scripts/git_install.sh uninstall
```

