# nodejs_install.sh 使用说明

## 脚本简介
用于自动安装与卸载 Node.js 及其包管理器 npm。脚本专门针对 LTS (长期支持版) 进行了优化，并支持自动设置淘宝 npm 镜像源以加速国内网络环境下的包下载。

## 使用示例

### 1. 安装最新的 LTS 版本 (推荐)
自动拉取目前官方推荐的长期支持版本（如 Node.js 20 或 22）：
```bash
sudo ./scripts/nodejs_install.sh lts
```

### 2. 安装特定大版本
如果您明确需要 Node 18：
```bash
sudo ./scripts/nodejs_install.sh 18
```

### 3. 列出可用 Node.js 版本
```bash
./scripts/nodejs_install.sh list
```

### 4. 卸载 Node.js 环境
彻底移除 Node 二进制和全局 node_modules：
```bash
sudo ./scripts/nodejs_install.sh uninstall
```

