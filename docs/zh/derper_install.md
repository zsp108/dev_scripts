# derper_install.sh 使用说明

## 脚本简介
Tailscale DERP 中继节点的自动化部署与管理脚本。
DERP (Designated Encrypted Relay for Packets) 节点用于在 Tailscale P2P 直连失败时，进行高强度加密的中继通信。此脚本自动为您配置域名、端口，并利用 SysV 服务进行持久化管理。

## 使用示例

### 1. 默认安装 (基于脚本内置变量)
如果您已经修改了脚本内的默认参数，可以直接运行：
```bash
sudo ./scripts/derper_install.sh
```

### 2. 传递参数运行
顺序为 `域名` -> `端口` -> `安装路径` -> `日志文件`：
```bash
sudo ./scripts/derper_install.sh derp.my-domain.com 50003 /opt/derp /var/log/derper.log
```

### 3. 基于环境变量运行 (推荐自动化运维方案)
```bash
export DOMAIN="derp.my-domain.com"
export PORT="50003"
sudo -E ./scripts/derper_install.sh
```

