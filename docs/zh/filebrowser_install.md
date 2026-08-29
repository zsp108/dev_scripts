# filebrowser_install.sh 使用说明

## 脚本简介
这是一个专为 Linux（Ubuntu / Debian / CentOS / RHEL）打造的 FileBrowser Web 文件管理器一键部署与多用户隔离管理脚本：
1. **自动感知与跨服务 Host 复用**：
   - 自动探测内网 IP 与云服务器 ECS 公网 IP；
   - **智能复用 Samba 设置**：若本机已通过 `samba_install.sh` 配置过自定义公网 IP 或域名，FileBrowser 会自动识别并将其作为默认推荐，无需重复输入！
2. **多用户严格 Scope 隔离**：支持为每个用户分配独立的物理目录，普通用户只能在自己的 Scope 目录下读写，超级管理员 `admin` 可纵览全局。
3. **独立服务托管**：自动适配 systemd 或 SysVinit 注册系统自启服务。

---

## 常用命令示例

### 1. 交互式菜单与安装（推荐）
运行脚本即可进入管理面板，安装时会自动提示您确认或自定义 Web 访问使用的 IP / 域名：
```bash
sudo ./scripts/filebrowser_install.sh
```

### 2. 命令行快速安装（支持指定公网 IP / 域名）
支持传入 `--host` 参数直接指定服务器公网 IP 或域名：
```bash
# 格式：sudo ./scripts/filebrowser_install.sh install [全局根目录] [端口] [管理员密码] [DB路径] [--host IP或域名]
sudo ./scripts/filebrowser_install.sh install /personal/samba 8080 MyAdminPass123 /etc/filebrowser/filebrowser.db --host 123.56.78.90
```

### 3. 多用户管理与 Scope 隔离
```bash
# 添加隔离普通用户 (例如与 Samba 隔离目录协同)
sudo ./scripts/filebrowser_install.sh adduser alice AlicePass123 /personal/samba/alice

# 查看所有已注册用户
sudo ./scripts/filebrowser_install.sh lsusers

# 重置用户密码
sudo ./scripts/filebrowser_install.sh setpasswd alice NewPass456

# 删除用户
sudo ./scripts/filebrowser_install.sh deluser alice
```

### 4. 服务启停与端口/域名修改
```bash
# 修改 Web 监听端口
sudo ./scripts/filebrowser_install.sh setport 8088

# 查看运行状态
sudo ./scripts/filebrowser_install.sh status

# 启停与重启
sudo ./scripts/filebrowser_install.sh start
sudo ./scripts/filebrowser_install.sh stop
sudo ./scripts/filebrowser_install.sh restart
```
