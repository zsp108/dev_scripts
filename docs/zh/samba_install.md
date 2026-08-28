# samba_install.sh 使用说明

## 脚本简介
这是一个极其强大的 Samba 自动化部署脚本。它不仅安装基础的 Samba 服务，还做了深度优化：
1. **多用户严格存储隔离**：默认基目录为 `/personal/samba/<用户名>`，实现用户私人空间。
2. **自定义端口支持**：能够突破运营商对 445 端口的封锁，支持自定义监听端口（如 10445）。
3. **跨端访问优化**：针对 macOS Finder 做了原生优化支持；针对 Windows 优化了高速传输。

## 使用示例

### 1. 交互式自动化部署
启动脚本后，它会询问您所需的配置参数并自动完成系统服务注册、防火墙放行等操作：
```bash
sudo ./scripts/samba_install.sh
```

### 2. 运维指南
安装完毕后，在日常使用中，您可以通过以下命令管理用户密码：
```bash
# 新增用户或修改现有用户密码
sudo smbpasswd -a <username>
```

控制服务启停：
```bash
sudo systemctl restart smbd
sudo systemctl enable smbd
```

